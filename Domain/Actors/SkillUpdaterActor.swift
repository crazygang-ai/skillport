import Foundation

public actor SkillUpdaterActor {
    private let git: GitActor
    private let cache: CommitHashCache
    private let repoCache: RepoCacheActor
    private let lockFile: LockFileActor?

    public init(
        git: GitActor,
        cache: CommitHashCache,
        repoCache: RepoCacheActor? = nil,
        lockFile: LockFileActor? = nil
    ) {
        self.git = git
        self.cache = cache
        self.repoCache = repoCache ?? RepoCacheActor(git: git)
        self.lockFile = lockFile
    }

    public func checkStatus(name: String, source: SkillSource, canonical: URL)
        async throws -> UpdateStatus
    {
        try await checkStatus(name: name, source: source, canonical: canonical, remoteURLOverride: nil)
    }

    /// Testable variant: `remoteURLOverride` lets tests swap the github URL for a local
    /// file:// bare repo. Production code should call the 3-arg variant above.
    public func checkStatus(
        name: String, source: SkillSource, canonical: URL, remoteURLOverride: URL?
    ) async throws -> UpdateStatus {
        switch source {
        case .local, .registry:
            return .upToDate
        case .github(let owner, let repo, let ref):
            // 查 lockfile 取 skillPath + baseline folderHash + dismissedUpdate。
            // 没注入 lockFile 时退化到整仓 tree hash（老行为）。
            let locked: LockedSkill? = await readLocked(name: name)
            let skillPath = locked?.skillPath ?? ""
            let baseline = locked?.skillFolderHash
            let dismissed = locked?.dismissedUpdate
            let id = SkillIdentity.compute(name: name, source: source)
            let url =
                remoteURLOverride
                ?? URL(string: "https://github.com/\(owner)/\(repo).git")!

            // 拿到 remote subdir tree hash 的流程：acquire cache → subdirTreeHash。
            let remoteSubHash: String
            do {
                let cached = try await repoCache.acquire(url: url, ref: ref)
                remoteSubHash = try await git.subdirTreeHash(
                    in: cached, subdir: skillPath, ref: "HEAD"
                )
            } catch {
                // 远程/本地 clone 不通：回落到 commit hash cache 做弱判断。
                if let cached = await cache.get(identity: id),
                    let head = try? await git.headHash(in: canonical),
                    cached == head
                {
                    return .upToDate
                }
                return .unknown
            }

            // 有 baseline 就用 subdir tree hash 精确对比。
            if let baseline, !baseline.isEmpty {
                if remoteSubHash == baseline {
                    try? await cache.set(identity: id, hash: remoteSubHash)
                    return .upToDate
                }
                if let dismissed, dismissed == remoteSubHash {
                    return .upToDate
                }
                return .available(remoteHash: remoteSubHash)
            }

            // 没 baseline（老装 skill 没写 skillFolderHash）：退回 commit-hash 粗判，
            // 同时把 tree hash 存进 cache 以便下一轮。
            let localHead = (try? await git.headHash(in: canonical)) ?? ""
            if !remoteSubHash.isEmpty, remoteSubHash == localHead {
                try? await cache.set(identity: id, hash: remoteSubHash)
                return .upToDate
            }
            if let dismissed, dismissed == remoteSubHash {
                return .upToDate
            }
            return .available(remoteHash: remoteSubHash)
        }
    }

    /// Apply the latest remote state to `canonical`. Atomic with rollback on failure.
    /// Returns the new `skillFolderHash` so the caller can update lockfile.
    @discardableResult
    public func apply(
        name: String,
        source: SkillSource,
        canonical: URL,
        skillPath: String?
    ) async throws -> String {
        try await apply(
            name: name, source: source, canonical: canonical,
            skillPath: skillPath, remoteURLOverride: nil
        )
    }

    /// Testable variant — see `checkStatus(remoteURLOverride:)`.
    @discardableResult
    public func apply(
        name: String,
        source: SkillSource,
        canonical: URL,
        skillPath: String?,
        remoteURLOverride: URL?
    ) async throws -> String {
        guard case .github(let owner, let repo, let ref) = source else {
            throw SkillportError.unexpected("apply() only supports github sources (got \(source))")
        }
        let url =
            remoteURLOverride
            ?? URL(string: "https://github.com/\(owner)/\(repo).git")!
        let cached = try await repoCache.acquire(url: url, ref: ref)

        let subdir = (skillPath ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let src = subdir.isEmpty ? cached : cached.appendingPathComponent(subdir)
        guard FileManager.default.fileExists(atPath: src.appendingPathComponent("SKILL.md").path)
        else {
            throw SkillportError.fileIO(
                path: src,
                reason: "SKILL.md not found in cached repo at '\(subdir)'"
            )
        }

        let parent = canonical.deletingLastPathComponent()
        let suffix = UUID().uuidString
        let tmp = parent.appendingPathComponent(".\(canonical.lastPathComponent).tmp-\(suffix)")
        let backup = parent.appendingPathComponent(".\(canonical.lastPathComponent).bak-\(suffix)")
        let fm = FileManager.default

        // 1. 复制新内容到 tmp（去 .git）。失败 → 清 tmp 抛错。
        do {
            try SkillInstallerActor.copyDirectory(from: src, to: tmp, excluding: [".git"])
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }

        // 2. 原子 swap：canonical → backup → tmp → canonical。
        let canonicalExisted = fm.fileExists(atPath: canonical.path)
        do {
            if canonicalExisted {
                try fm.moveItem(at: canonical, to: backup)
            }
            try fm.moveItem(at: tmp, to: canonical)
        } catch {
            // 回滚
            if canonicalExisted, fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: canonical)
                try? fm.moveItem(at: backup, to: canonical)
            }
            try? fm.removeItem(at: tmp)
            throw error
        }

        // 3. 成功 → 清 backup。
        if fm.fileExists(atPath: backup.path) {
            try? fm.removeItem(at: backup)
        }

        // 4. 算新 folderHash；同时刷新 commit hash cache。
        let newHash = try await git.subdirTreeHash(in: cached, subdir: subdir, ref: "HEAD")
        let id = SkillIdentity.compute(name: name, source: source)
        if let commit = try? await git.headHash(in: cached) {
            try? await cache.set(identity: id, hash: commit)
        }
        return newHash
    }

    // MARK: - Internals

    private func readLocked(name: String) async -> LockedSkill? {
        guard let lockFile else { return nil }
        guard let lock = try? await lockFile.read() else { return nil }
        return lock.skills.first { $0.name == name }
    }
}
