import Foundation

public actor SkillManagerActor {
    public let events: AsyncStream<DomainEvent>
    private let eventsContinuation: AsyncStream<DomainEvent>.Continuation

    private let scanner: SkillScannerActor
    private let installer: SkillInstallerActor
    private let updater: SkillUpdaterActor
    private let batchChecker: BatchUpdateCheckerActor
    private let watcher: FileWatcherActor
    private let lockFile: LockFileActor

    private var watchTask: Task<Void, Never>?
    private var updateStatuses: [SkillIdentity: UpdateStatus] = [:]

    public init(
        scanner: SkillScannerActor,
        installer: SkillInstallerActor,
        updater: SkillUpdaterActor,
        batchChecker: BatchUpdateCheckerActor,
        watcher: FileWatcherActor,
        lockFile: LockFileActor
    ) {
        self.scanner = scanner
        self.installer = installer
        self.updater = updater
        self.batchChecker = batchChecker
        self.watcher = watcher
        self.lockFile = lockFile
        let (stream, continuation) = AsyncStream<DomainEvent>.makeStream()
        self.events = stream
        self.eventsContinuation = continuation
    }

    deinit {
        eventsContinuation.finish()
    }

    public var isWatching: Bool {
        watchTask != nil
    }

    @discardableResult
    public func rescan(home: URL) async throws -> [Skill] {
        let scanned = try await scanner.scanAll(home: home)
        // Scanner 默认把 source 设为 .local；lockfile 里持有真实 source。
        // 合并后避免 installGitHub 之后 rescan 把 source 错误回退为 .local。
        let lock: LockFile
        do {
            let readResult = try await lockFile.readWithRecoveryNotice()
            lock = readResult.lockFile
            if let recoveryError = readResult.recoveryError {
                eventsContinuation.yield(.error(recoveryError))
            }
        } catch {
            let reason = (error as? SkillportError).map { "\($0)" } ?? "\(error)"
            eventsContinuation.yield(
                .error(.invalidLockFile(reason: reason))
            )
            lock = LockFile(skills: [])
        }
        var sourceByResolvedPath: [String: SkillSource] = [:]
        for locked in lock.skills {
            sourceByResolvedPath[locked.path.resolvingSymlinksInPath().path] = locked.source
        }
        let merged: [Skill] = scanned.map { s in
            let realSource = sourceByResolvedPath[s.path.resolvingSymlinksInPath().path] ?? s.source
            let id = SkillIdentity.compute(name: s.name, source: realSource)
            let updateStatus = updateStatuses[id] ?? s.updateStatus
            return Skill(
                name: s.name,
                path: s.path,
                source: realSource,
                frontmatter: s.frontmatter,
                installedAgents: s.installedAgents,
                updateStatus: updateStatus
            )
        }
        let currentIDs = Set(merged.map(\.id))
        updateStatuses = updateStatuses.filter { currentIDs.contains($0.key) }
        eventsContinuation.yield(.skillsReloaded(skills: merged))
        return merged
    }

    public func startWatching(home: URL) async {
        let fm = FileManager.default
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try? fm.createDirectory(at: canonicalBase, withIntermediateDirectories: true)

        // 同时监听每个 agent 的 skillsDir（外部 CLI 直接往 `.claude/skills` 写 skill
        // 也能触发 rescan）。只收录已存在的目录，FSEvents 对不存在的 path 会忽略但
        // 也会产生噪声。
        var paths: [URL] = [canonicalBase]
        for agent in Agent.defaultAgents(home: home) {
            if fm.fileExists(atPath: agent.skillsDir.path) {
                paths.append(agent.skillsDir)
            }
        }

        let stream = await watcher.start(paths: paths)
        watchTask = Task { [weak self] in
            // 100ms debounce — 合并 FSEvents 的洪峰（git 操作、批量安装等）。
            let debounce: Duration = .milliseconds(100)
            var pending = false
            var lastFire: ContinuousClock.Instant? = nil
            for await _ in stream {
                let now = ContinuousClock.now
                if let last = lastFire, now - last < debounce, pending { continue }
                pending = true
                try? await Task.sleep(for: debounce)
                lastFire = ContinuousClock.now
                pending = false
                _ = try? await self?.rescan(home: home)
            }
        }
    }

    public func stopWatching() async {
        watchTask?.cancel()
        watchTask = nil
        await watcher.stop()
    }

    public func toggleAgent(name: String, agent: AgentID, install: Bool, home: URL) async throws {
        try await installer.toggleAgent(name: name, agent: agent, install: install, home: home)
        // 重新扫以更新 installedAgents
        _ = try await rescan(home: home)
    }

    public func installLocal(from source: URL, home: URL, installTo: Set<AgentID>) async throws -> Skill {
        let skill = try await installer.installLocal(from: source, home: home, installTo: installTo)
        updateStatuses[skill.id] = skill.updateStatus
        _ = try await rescan(home: home)
        return skill
    }

    public func installGitHub(
        owner: String, repo: String, ref: String,
        skillId: String? = nil,
        home: URL, installTo: Set<AgentID>
    ) async throws -> Skill {
        let skill = try await installer.installGitHub(
            owner: owner, repo: repo, ref: ref,
            skillId: skillId,
            home: home, installTo: installTo
        )
        updateStatuses[skill.id] = skill.updateStatus
        _ = try await rescan(home: home)
        return skill
    }

    public func uninstall(name: String, home: URL) async throws {
        try await installer.uninstall(name: name, home: home)
        _ = try await rescan(home: home)
    }

    public func checkAllUpdates(skills: [Skill]) async throws -> [SkillIdentity: UpdateStatus] {
        let results = try await batchChecker.checkAll(skills: skills)
        for (id, status) in results {
            updateStatuses[id] = status
            eventsContinuation.yield(.skillUpdateStatusChanged(id: id, status: status))
        }
        let available = results.values.filter {
            if case .available = $0 { return true }
            return false
        }.count
        eventsContinuation.yield(.batchUpdateCheckCompleted(available: available))
        return results
    }

    /// Apply a pending update: atomic swap on canonical, refresh lockfile baseline.
    public func applyUpdate(name: String, home: URL) async throws {
        let lock = try await lockFile.read()
        guard let locked = lock.skills.first(where: { $0.name == name }) else {
            throw SkillportError.unexpected("no lockfile entry for '\(name)'")
        }
        let newHash = try await updater.apply(
            name: name,
            source: locked.source,
            canonical: locked.path,
            skillPath: locked.skillPath
        )
        let updated = LockedSkill(
            name: locked.name,
            source: locked.source,
            installedAt: locked.installedAt,
            commitHash: locked.commitHash,
            path: locked.path,
            skillFolderHash: newHash,
            skillPath: locked.skillPath,
            updatedAt: Date(),
            dismissedUpdate: nil,
            lastSelectedAgents: locked.lastSelectedAgents
        )
        try await lockFile.upsert(updated)
        let id = SkillIdentity.compute(name: name, source: locked.source)
        updateStatuses[id] = .upToDate
        eventsContinuation.yield(.skillUpdateStatusChanged(id: id, status: .upToDate))
        _ = try await rescan(home: home)
    }

    /// Record that the user dismissed an available update for this skill.
    /// Next `checkStatus` will return `.upToDate` as long as the remote hash stays the same.
    public func dismissUpdate(name: String, remoteHash: String) async throws {
        let lock = try await lockFile.read()
        guard let locked = lock.skills.first(where: { $0.name == name }) else {
            throw SkillportError.unexpected("no lockfile entry for '\(name)'")
        }
        let updated = LockedSkill(
            name: locked.name,
            source: locked.source,
            installedAt: locked.installedAt,
            commitHash: locked.commitHash,
            path: locked.path,
            skillFolderHash: locked.skillFolderHash,
            skillPath: locked.skillPath,
            updatedAt: locked.updatedAt,
            dismissedUpdate: remoteHash,
            lastSelectedAgents: locked.lastSelectedAgents
        )
        try await lockFile.upsert(updated)
        let id = SkillIdentity.compute(name: name, source: locked.source)
        updateStatuses[id] = .upToDate
        eventsContinuation.yield(.skillUpdateStatusChanged(id: id, status: .upToDate))
    }
}
