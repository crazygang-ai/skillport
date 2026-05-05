import CryptoKit
import Foundation

public actor SkillInstallerActor {
    public typealias DirectoryCopy = @Sendable (_ src: URL, _ dest: URL, _ excludes: Set<String>) throws -> Void

    private let git: GitActor
    private let symlinker: SymlinkManagerActor
    private let lockFile: LockFileActor
    private let cache: CommitHashCache
    private let repoCache: RepoCacheActor
    private let localImporter: LocalImporter
    private let directoryCopy: DirectoryCopy

    public init(
        git: GitActor,
        symlinker: SymlinkManagerActor,
        lockFile: LockFileActor,
        cache: CommitHashCache,
        repoCache: RepoCacheActor? = nil,
        localImporter: LocalImporter = LocalImporter(),
        directoryCopy: @escaping DirectoryCopy = { src, dest, excludes in
            try SkillInstallerActor.copyDirectory(from: src, to: dest, excluding: excludes)
        }
    ) {
        self.git = git
        self.symlinker = symlinker
        self.lockFile = lockFile
        self.cache = cache
        self.repoCache = repoCache ?? RepoCacheActor(git: git)
        self.localImporter = localImporter
        self.directoryCopy = directoryCopy
    }

    @discardableResult
    public func installLocal(from source: URL, home: URL, installTo: Set<AgentID>) async throws -> Skill {
        let oldLock = try await lockFile.read()
        let canonical = try localImporter.importSkill(from: source, home: home)
        let name = canonical.lastPathComponent
        let skillSource = SkillSource.local(path: source)
        let locked = LockedSkill(
            name: name,
            source: skillSource,
            installedAt: Date(),
            commitHash: nil,
            path: canonical,
            skillFolderHash: nil,
            skillPath: nil,
            updatedAt: Date(),
            dismissedUpdate: nil,
            lastSelectedAgents: installTo.isEmpty ? nil : installTo
        )

        var agents: Set<AgentID> = []
        do {
            try await lockFile.upsert(locked)
            for agentID in installTo {
                try await toggleAgent(name: name, agent: agentID, install: true, home: home)
                agents.insert(agentID)
            }
        } catch {
            try? await lockFile.write(oldLock)
            for agentID in agents {
                if let agentConfig = Agent.defaultAgents(home: home).first(where: { $0.id == agentID }) {
                    let link = agentConfig.skillsDir.appendingPathComponent(name)
                    try? await symlinker.removeInstallation(at: link, canonical: canonical)
                }
            }
            try? FileManager.default.removeItem(at: canonical)
            throw error
        }

        let raw = (try? String(contentsOf: canonical.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let parsed = (try? SKILLMdParser.parse(raw)) ?? .init(metadata: SKILLMetadata(), body: raw)

        return Skill(
            name: name,
            path: canonical,
            source: skillSource,
            frontmatter: parsed.metadata,
            installedAgents: agents,
            updateStatus: .unknown
        )
    }

    public func installGitHub(
        owner: String, repo: String, ref: String,
        skillId: String? = nil,
        home: URL, installTo: Set<AgentID>
    ) async throws -> Skill {
        let url = URL(string: "https://github.com/\(owner)/\(repo).git")!
        return try await installGitHub(
            sourceURL: url,
            owner: owner, repo: repo, ref: ref,
            skillId: skillId ?? repo,
            home: home, installTo: installTo
        )
    }

    /// Testable overload — accepts any source URL (file:// for tests, https:// for prod).
    public func installGitHub(
        sourceURL: URL,
        owner: String, repo: String, ref: String,
        skillId: String,
        home: URL, installTo: Set<AgentID>
    ) async throws -> Skill {
        let fm = FileManager.default
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: canonicalBase, withIntermediateDirectories: true)

        // 拿共享缓存 repo；若是第一次 clone 由 RepoCacheActor 负责。
        let cached = try await repoCache.acquire(url: sourceURL, ref: ref)

        // 定位 skill 源目录 + 相对路径。
        let (srcDir, relativePath) = try Self.locateSkill(
            in: cached, skillId: skillId, isSingleRepo: skillId == repo
        )

        let oldLock = try await lockFile.read()
        let source = SkillSource.github(owner: owner, repo: repo, ref: ref)
        let storageName = Self.storageName(
            preferred: skillId,
            source: source,
            skillPath: relativePath,
            canonicalBase: canonicalBase,
            lock: oldLock
        )
        let dest = canonicalBase.appendingPathComponent(storageName, isDirectory: true)
        let suffix = UUID().uuidString
        let tmp = canonicalBase.appendingPathComponent(".\(storageName).tmp-\(suffix)", isDirectory: true)
        let backup = canonicalBase.appendingPathComponent(".\(storageName).bak-\(suffix)", isDirectory: true)

        // 复制到 staging（去掉 `.git` 避免把 repo 历史带进 skill 目录）。失败时旧 canonical 不动。
        do {
            try directoryCopy(srcDir, tmp, [".git"])
            guard fm.fileExists(atPath: tmp.appendingPathComponent("SKILL.md").path) else {
                throw SkillportError.fileIO(path: tmp, reason: "staged skill missing SKILL.md")
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }

        // 在 cached（有 .git）里算 hash；dest 没有 .git 算不了。
        let commitHash = try? await git.headHash(in: cached)
        let folderHash = try? await git.subdirTreeHash(
            in: cached, subdir: relativePath ?? "", ref: "HEAD"
        )
        let identity = SkillIdentity.compute(name: storageName, source: source)
        let now = Date()
        let locked = LockedSkill(
            name: storageName,
            source: source,
            installedAt: now,
            commitHash: commitHash,
            path: dest,
            skillFolderHash: folderHash,
            skillPath: relativePath,
            updatedAt: now,
            dismissedUpdate: nil,
            lastSelectedAgents: installTo.isEmpty ? nil : installTo
        )
        let raw =
            (try? String(contentsOf: tmp.appendingPathComponent("SKILL.md"), encoding: .utf8))
            ?? ""
        let parsed = (try? SKILLMdParser.parse(raw)) ?? .init(metadata: SKILLMetadata(), body: raw)

        let canonicalExisted = fm.fileExists(atPath: dest.path)
        do {
            if canonicalExisted {
                try fm.moveItem(at: dest, to: backup)
            }
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            if canonicalExisted, fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: backup, to: dest)
            }
            try? fm.removeItem(at: tmp)
            throw error
        }

        var agents: Set<AgentID> = []
        do {
            try await lockFile.upsert(locked)
            for agentID in installTo {
                try await toggleAgent(name: storageName, agent: agentID, install: true, home: home)
                agents.insert(agentID)
            }
        } catch {
            try? await lockFile.write(oldLock)
            for agentID in agents {
                if let agentConfig = Agent.defaultAgents(home: home).first(where: { $0.id == agentID }) {
                    let link = agentConfig.skillsDir.appendingPathComponent(storageName)
                    try? await symlinker.removeInstallation(at: link, canonical: dest)
                }
            }
            if canonicalExisted, fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: backup, to: dest)
            } else {
                try? fm.removeItem(at: dest)
            }
            throw error
        }

        if fm.fileExists(atPath: backup.path) {
            try? fm.removeItem(at: backup)
        }
        if let folderHash {
            try? await cache.set(identity: identity, hash: folderHash)
        } else if let commitHash {
            try? await cache.set(identity: identity, hash: commitHash)
        }
        return Skill(
            name: storageName,
            path: dest,
            source: source,
            frontmatter: parsed.metadata,
            installedAgents: agents,
            updateStatus: .upToDate
        )
    }

    /// Remove Skillport-managed symlinks, delete canonical files, drop lockfile entry.
    public func uninstall(name: String, home: URL) async throws {
        let canonical = home.appendingPathComponent(".agents/skills/\(name)")
        let fm = FileManager.default
        // 撤销所有 agent 下的安装——symlink 或 copy 都 handle。
        for agent in Agent.defaultAgents(home: home) {
            let link = agent.skillsDir.appendingPathComponent(name)
            try? await symlinker.removeInstallation(at: link, canonical: canonical)
        }
        // Delete canonical files + drop lockfile entry.
        if fm.fileExists(atPath: canonical.path) {
            try fm.removeItem(at: canonical)
        }
        try await lockFile.remove(name: name)
    }

    public func toggleAgent(name: String, agent: AgentID, install: Bool, home: URL) async throws {
        let canonical = home.appendingPathComponent(".agents/skills/\(name)")
        guard let agentConfig = Agent.defaultAgents(home: home).first(where: { $0.id == agent }) else {
            return
        }
        let link = agentConfig.skillsDir.appendingPathComponent(name)
        if install {
            // 若 agent 的 fallback 已能读到同一 canonical，就不建冗余 symlink。
            if await symlinker.canInherit(
                target: canonical, linkURL: link, fallbackChain: agentConfig.fallbackChain
            ) {
                return
            }
            try await symlinker.link(target: canonical, at: link)
        } else {
            try await symlinker.removeInstallation(at: link, canonical: canonical)
        }
    }

    // MARK: - Helpers

    /// 在已 clone 的 repo 里定位 skill 目录：
    /// - `isSingleRepo == true` 且根有 SKILL.md → 用根；
    /// - 否则递归找 SKILL.md，选 `lastPathComponent == skillId`；若找不到再看根；
    /// - 都没有 → 抛错。
    /// 返回 (目录 URL, 相对 repo 根的路径)。单 skill 根目录返回 path = nil。
    private static func locateSkill(
        in repoRoot: URL, skillId: String, isSingleRepo: Bool
    ) throws -> (URL, String?) {
        let fm = FileManager.default
        let rootSkill = repoRoot.appendingPathComponent("SKILL.md")
        if isSingleRepo, fm.fileExists(atPath: rootSkill.path) {
            return (repoRoot, nil)
        }
        let skills = findSkillDirs(root: repoRoot, maxDepth: 5)
        // 必须名字匹配才算命中；否则报错，避免"乱装到错位置"。
        if let match = skills.first(where: { $0.lastPathComponent == skillId }) {
            let relative = relativePath(of: match, relativeTo: repoRoot)
            return (match, relative.isEmpty ? nil : relative)
        }
        throw SkillportError.fileIO(
            path: repoRoot,
            reason: "SKILL.md not found for skillId '\(skillId)' in cloned repo"
        )
    }

    /// 深度优先扫描 repo，返回所有含 `SKILL.md` 的目录。
    /// 即使当前目录已是一个 skill，也继续向下扫描，支持 root skill + subskills 共存的 repo。
    /// 跳过 `.git` / `node_modules` / `__MACOSX` / 除白名单外的 dotfile 目录。
    static func findSkillDirs(root: URL, maxDepth: Int = 5) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        let dotWhitelist: Set<String> = [
            ".claude", ".cursor", ".codex", ".gemini", ".kiro", ".codebuddy",
            ".openclaw", ".trae", ".copilot", ".agents", ".config",
        ]
        let alwaysSkip: Set<String> = [".git", "node_modules", "__MACOSX"]
        func walk(_ dir: URL, _ depth: Int) {
            if depth > maxDepth { return }
            if fm.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path) {
                result.append(dir)
            }
            guard
                let entries = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []
                )
            else { return }
            for entry in entries {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue
                else { continue }
                let name = entry.lastPathComponent
                if alwaysSkip.contains(name) { continue }
                if name.hasPrefix("."), !dotWhitelist.contains(name) { continue }
                walk(entry, depth + 1)
            }
        }
        walk(root, 0)
        return result
    }

    private static func relativePath(of url: URL, relativeTo base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath == basePath { return "" }
        if urlPath.hasPrefix(basePath + "/") {
            return String(urlPath.dropFirst(basePath.count + 1))
        }
        return url.lastPathComponent
    }

    private static func storageName(
        preferred: String,
        source: SkillSource,
        skillPath: String?,
        canonicalBase: URL,
        lock: LockFile
    ) -> String {
        let normalizedPath = normalizedSkillPath(skillPath)
        if let existing = lock.skills.first(where: {
            $0.source == source && normalizedSkillPath($0.skillPath) == normalizedPath
        }) {
            return existing.name
        }

        let fm = FileManager.default
        let preferredPath = canonicalBase.appendingPathComponent(preferred, isDirectory: true)
        let preferredInLock = lock.skills.contains { $0.name == preferred }
        if !preferredInLock && !fm.fileExists(atPath: preferredPath.path) {
            return preferred
        }

        let suffix = shortHash("\(source)|\(normalizedPath)")
        var candidate = "\(preferred)--\(suffix)"
        var counter = 2
        while lock.skills.contains(where: { $0.name == candidate })
            || fm.fileExists(atPath: canonicalBase.appendingPathComponent(candidate).path)
        {
            candidate = "\(preferred)--\(suffix)-\(counter)"
            counter += 1
        }
        return candidate
    }

    private static func normalizedSkillPath(_ path: String?) -> String {
        (path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func shortHash(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(12))
    }

    /// 顶层复制，跳过 `excluding` 中的 entry 名（如 `.git`）。嵌套层级保持原样。
    public static func copyDirectory(from src: URL, to dest: URL, excluding excludes: Set<String>) throws {
        let fm = FileManager.default
        if let symlink = try firstIncludedSymlink(in: src, excludingTopLevelNames: excludes) {
            throw SkillportError.fileIO(
                path: symlink,
                reason: "remote skill refuses source trees containing symlinks"
            )
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let entries = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: [])
        for entry in entries {
            if excludes.contains(entry.lastPathComponent) { continue }
            let target = dest.appendingPathComponent(entry.lastPathComponent)
            try fm.copyItem(at: entry, to: target)
        }
    }

    private static func firstIncludedSymlink(
        in url: URL,
        excludingTopLevelNames excludes: Set<String>
    ) throws -> URL? {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true {
            return url
        }
        guard values.isDirectory == true else {
            return nil
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for entry in entries {
            if excludes.contains(entry.lastPathComponent) { continue }
            if let symlink = try firstSymlink(in: entry) {
                return symlink
            }
        }
        return nil
    }

    private static func firstSymlink(in url: URL) throws -> URL? {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true {
            return url
        }
        guard values.isDirectory == true else {
            return nil
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for entry in entries {
            if let symlink = try firstSymlink(in: entry) {
                return symlink
            }
        }
        return nil
    }
}
