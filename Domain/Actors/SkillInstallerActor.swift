import Foundation

public actor SkillInstallerActor {
    private let git: GitActor
    private let symlinker: SymlinkManagerActor
    private let lockFile: LockFileActor
    private let cache: CommitHashCache
    private let repoCache: RepoCacheActor
    private let localImporter: LocalImporter

    public init(
        git: GitActor,
        symlinker: SymlinkManagerActor,
        lockFile: LockFileActor,
        cache: CommitHashCache,
        repoCache: RepoCacheActor? = nil,
        localImporter: LocalImporter = LocalImporter()
    ) {
        self.git = git
        self.symlinker = symlinker
        self.lockFile = lockFile
        self.cache = cache
        self.repoCache = repoCache ?? RepoCacheActor(git: git)
        self.localImporter = localImporter
    }

    @discardableResult
    public func installLocal(from source: URL, home: URL, installTo: Set<AgentID>) async throws -> Skill {
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
        try await lockFile.upsert(locked)

        var agents: Set<AgentID> = []
        for agentID in installTo {
            try await toggleAgent(name: name, agent: agentID, install: true, home: home)
            agents.insert(agentID)
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
        let dest = canonicalBase.appendingPathComponent(skillId, isDirectory: true)

        // 幂等：dest 已存在（旧版本、broken install）→ 覆盖，不 throw。
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }

        // 拿共享缓存 repo；若是第一次 clone 由 RepoCacheActor 负责。
        let cached = try await repoCache.acquire(url: sourceURL, ref: ref)

        // 定位 skill 源目录 + 相对路径。
        let (srcDir, relativePath) = try Self.locateSkill(
            in: cached, skillId: skillId, isSingleRepo: skillId == repo
        )

        // 复制到 canonical dest（去掉 `.git` 避免把 repo 历史带进 skill 目录）。
        try Self.copyDirectory(from: srcDir, to: dest, excluding: [".git"])

        // 在 cached（有 .git）里算 hash；dest 没有 .git 算不了。
        let commitHash = try? await git.headHash(in: cached)
        let folderHash = try? await git.subdirTreeHash(
            in: cached, subdir: relativePath ?? "", ref: "HEAD"
        )
        let identity = SkillIdentity.compute(
            name: skillId, source: .github(owner: owner, repo: repo, ref: ref)
        )
        if let commitHash {
            try await cache.set(identity: identity, hash: commitHash)
        }
        let now = Date()
        let locked = LockedSkill(
            name: skillId,
            source: .github(owner: owner, repo: repo, ref: ref),
            installedAt: now,
            commitHash: commitHash,
            path: dest,
            skillFolderHash: folderHash,
            skillPath: relativePath,
            updatedAt: now,
            dismissedUpdate: nil,
            lastSelectedAgents: installTo.isEmpty ? nil : installTo
        )
        try await lockFile.upsert(locked)
        var agents: Set<AgentID> = []
        for agentID in installTo {
            try await toggleAgent(name: skillId, agent: agentID, install: true, home: home)
            agents.insert(agentID)
        }
        let raw =
            (try? String(contentsOf: dest.appendingPathComponent("SKILL.md"), encoding: .utf8))
            ?? ""
        let parsed = (try? SKILLMdParser.parse(raw)) ?? .init(metadata: SKILLMetadata(), body: raw)
        return Skill(
            name: skillId,
            path: dest,
            source: .github(owner: owner, repo: repo, ref: ref),
            frontmatter: parsed.metadata,
            installedAgents: agents,
            updateStatus: .upToDate
        )
    }

    /// Remove from all agents (including copy-type installs), delete canonical files, drop lockfile entry.
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

    /// 深度优先扫描 repo，返回所有含 `SKILL.md` 的目录。命中后不再深入。
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
                return
            }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { return }
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

    /// 顶层复制，跳过 `excluding` 中的 entry 名（如 `.git`）。嵌套层级保持原样。
    static func copyDirectory(from src: URL, to dest: URL, excluding excludes: Set<String>) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let entries = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: [])
        for entry in entries {
            if excludes.contains(entry.lastPathComponent) { continue }
            let target = dest.appendingPathComponent(entry.lastPathComponent)
            try fm.copyItem(at: entry, to: target)
        }
    }
}
