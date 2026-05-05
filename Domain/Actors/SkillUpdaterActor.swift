import CryptoKit
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
            let skillPath: String
            do {
                skillPath = try Self.normalizedRepoSubdir(locked?.skillPath)
            } catch {
                return .unknown
            }
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
                // 远程/本地 clone 不通：若本地 tree hash 与缓存的最新 tree hash 一致，
                // 至少可以判断本地没有落后于上次成功检查到的状态。
                if let cached = await cache.get(identity: id) {
                    if let localTreeHash = try? Self.computeLocalGitTreeHash(canonical),
                        cached == localTreeHash
                    {
                        return .upToDate
                    }
                    if let head = try? await git.headHash(in: canonical), cached == head {
                        return .upToDate
                    }
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

            // 没 baseline（老装 skill 没写 skillFolderHash）：计算 canonical 目录的 Git tree hash。
            // canonical 复制时会去掉 .git，所以不能用 git rev-parse HEAD 做比较。
            guard let localTreeHash = try? Self.computeLocalGitTreeHash(canonical) else {
                return .unknown
            }
            if !remoteSubHash.isEmpty, remoteSubHash == localTreeHash {
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

        let subdir = try Self.normalizedRepoSubdir(skillPath)
        let src = try Self.containedRepoURL(base: cached, subdir: subdir)
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
        try? await cache.set(identity: id, hash: newHash)
        return newHash
    }

    // MARK: - Internals

    private func readLocked(name: String) async -> LockedSkill? {
        guard let lockFile else { return nil }
        guard let lock = try? await lockFile.read() else { return nil }
        return lock.skills.first { $0.name == name }
    }

    private static func normalizedRepoSubdir(_ raw: String?) throws -> String {
        let trimmed = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, trimmed != "." else { return "" }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            throw SkillportError.fileIO(
                path: URL(fileURLWithPath: trimmed),
                reason: "skillPath escapes repo directory"
            )
        }
        return parts.joined(separator: "/")
    }

    private static func containedRepoURL(base: URL, subdir: String) throws -> URL {
        let basePath = base.standardizedFileURL.path
        let candidate = subdir.isEmpty ? base : base.appendingPathComponent(subdir, isDirectory: true)
        let candidatePath = candidate.standardizedFileURL.path
        if candidatePath == basePath || candidatePath.hasPrefix(basePath + "/") {
            return candidate
        }
        throw SkillportError.fileIO(
            path: candidate,
            reason: "skillPath escapes repo directory"
        )
    }

    private struct TreeEntry {
        let name: String
        let mode: String
        let hash: Data
        let isDirectory: Bool
    }

    private static let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    private static func computeLocalGitTreeHash(_ dir: URL) throws -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return nil
        }
        return try buildTreeHash(dir, allowEmpty: true)
    }

    private static func buildTreeHash(_ dir: URL, allowEmpty: Bool) throws -> String? {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        var entries: [TreeEntry] = []
        for url in urls where url.lastPathComponent != ".git" {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: url.path)
                entries.append(
                    TreeEntry(
                        name: url.lastPathComponent,
                        mode: "120000",
                        hash: gitObjectHash(type: "blob", content: Data(target.utf8)),
                        isDirectory: false
                    )
                )
            } else if values.isDirectory == true {
                guard let childHash = try buildTreeHash(url, allowEmpty: false),
                    let childHashData = dataFromHex(childHash)
                else {
                    continue
                }
                entries.append(
                    TreeEntry(
                        name: url.lastPathComponent,
                        mode: "40000",
                        hash: childHashData,
                        isDirectory: true
                    )
                )
            } else if values.isRegularFile == true {
                let attrs = try fm.attributesOfItem(atPath: url.path)
                let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let mode = (permissions & 0o111) != 0 ? "100755" : "100644"
                entries.append(
                    TreeEntry(
                        name: url.lastPathComponent,
                        mode: mode,
                        hash: gitObjectHash(type: "blob", content: try Data(contentsOf: url)),
                        isDirectory: false
                    )
                )
            }
        }

        if entries.isEmpty {
            return allowEmpty ? emptyTreeHash : nil
        }

        entries.sort { lhs, rhs in
            let lhsName = lhs.isDirectory ? "\(lhs.name)/" : lhs.name
            let rhsName = rhs.isDirectory ? "\(rhs.name)/" : rhs.name
            return Data(lhsName.utf8).lexicographicallyPrecedes(Data(rhsName.utf8))
        }

        var body = Data()
        for entry in entries {
            body.append(Data("\(entry.mode) \(entry.name)\0".utf8))
            body.append(entry.hash)
        }
        return hexString(gitObjectHash(type: "tree", content: body))
    }

    private static func gitObjectHash(type: String, content: Data) -> Data {
        var input = Data("\(type) \(content.count)\0".utf8)
        input.append(content)
        return Data(Insecure.SHA1.hash(data: input))
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
