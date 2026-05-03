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

    @discardableResult
    public func rescan(home: URL) async throws -> [Skill] {
        let scanned = try await scanner.scanAll(home: home)
        // Scanner 默认把 source 设为 .local；lockfile 里持有真实 source。
        // 合并后避免 installGitHub 之后 rescan 把 source 错误回退为 .local。
        let lock = (try? await lockFile.read()) ?? LockFile(skills: [])
        let sourceByName: [String: SkillSource] = Dictionary(
            uniqueKeysWithValues: lock.skills.map { ($0.name, $0.source) }
        )
        let merged: [Skill] = scanned.map { s in
            guard let realSource = sourceByName[s.name] else { return s }
            return Skill(
                name: s.name,
                path: s.path,
                source: realSource,
                frontmatter: s.frontmatter,
                installedAgents: s.installedAgents,
                updateStatus: s.updateStatus
            )
        }
        eventsContinuation.yield(.skillsReloaded(skills: merged))
        return merged
    }

    public func startWatching(home: URL) async {
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: canonicalBase, withIntermediateDirectories: true)
        let stream = await watcher.start(paths: [canonicalBase])
        watchTask = Task { [weak self] in
            for await _ in stream {
                try? await self?.rescan(home: home)
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
        _ = try await rescan(home: home)
        return skill
    }

    public func uninstall(name: String, home: URL) async throws {
        try await installer.uninstall(name: name, home: home)
        _ = try await rescan(home: home)
    }

    public func checkAllUpdates(skills: [Skill]) async throws -> [SkillIdentity: UpdateStatus] {
        let results = try await batchChecker.checkAll(skills: skills)
        let available = results.values.filter {
            if case .available = $0 { return true }
            return false
        }.count
        eventsContinuation.yield(.batchUpdateCheckCompleted(available: available))
        return results
    }
}
