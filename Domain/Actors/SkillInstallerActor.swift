import Foundation

public actor SkillInstallerActor {
    private let git: GitActor
    private let symlinker: SymlinkManagerActor
    private let lockFile: LockFileActor
    private let cache: CommitHashCache
    private let localImporter: LocalImporter

    public init(
        git: GitActor,
        symlinker: SymlinkManagerActor,
        lockFile: LockFileActor,
        cache: CommitHashCache,
        localImporter: LocalImporter = LocalImporter()
    ) {
        self.git = git
        self.symlinker = symlinker
        self.lockFile = lockFile
        self.cache = cache
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
            path: canonical
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
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try FileManager.default.createDirectory(
            at: canonicalBase, withIntermediateDirectories: true)
        let dest = canonicalBase.appendingPathComponent(skillId, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            throw SkillportError.fileIO(path: dest, reason: "destination already exists")
        }

        if skillId == repo {
            // Single-skill: clone directly to dest.
            if sourceURL.isFileURL {
                try await git.cloneLocal(from: sourceURL, to: dest, depth: 1)
            } else {
                try await git.clone(url: sourceURL, to: dest, ref: ref, depth: 1)
            }
        } else {
            // Multi-skill: clone to tmp, move matching subdir to dest.
            let tmpBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("skillport-install-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmpBase) }
            if sourceURL.isFileURL {
                try await git.cloneLocal(from: sourceURL, to: tmpBase, depth: 1)
            } else {
                try await git.clone(url: sourceURL, to: tmpBase, ref: ref, depth: 1)
            }

            let candidates = [
                tmpBase.appendingPathComponent(skillId),
                tmpBase.appendingPathComponent("skills").appendingPathComponent(skillId),
                tmpBase.appendingPathComponent(".claude/skills").appendingPathComponent(skillId),
            ]
            guard
                let src = candidates.first(where: {
                    FileManager.default.fileExists(
                        atPath: $0.appendingPathComponent("SKILL.md").path)
                })
            else {
                throw SkillportError.fileIO(
                    path: tmpBase,
                    reason: "SKILL.md not found for skillId '\(skillId)' in cloned repo"
                )
            }
            try FileManager.default.moveItem(at: src, to: dest)
        }

        let commitHash = try? await git.headHash(in: dest)
        let identity = SkillIdentity.compute(
            name: skillId, source: .github(owner: owner, repo: repo, ref: ref)
        )
        if let commitHash {
            try await cache.set(identity: identity, hash: commitHash)
        }
        let locked = LockedSkill(
            name: skillId,
            source: .github(owner: owner, repo: repo, ref: ref),
            installedAt: Date(),
            commitHash: commitHash,
            path: dest
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

    /// Remove from all agents, delete canonical files, drop lockfile entry.
    /// This is a complete removal; use `toggleAgent(install: false)` if you only
    /// want to unlink from a specific agent while keeping the canonical copy.
    public func uninstall(name: String, home: URL) async throws {
        let canonical = home.appendingPathComponent(".agents/skills/\(name)")
        // 撤销所有 agent symlinks
        for agent in Agent.defaultAgents(home: home) {
            let link = agent.skillsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: link.path) {
                try? await symlinker.unlink(at: link, expectedTarget: canonical)
            }
        }
        // Delete canonical files + drop lockfile entry.
        if FileManager.default.fileExists(atPath: canonical.path) {
            try FileManager.default.removeItem(at: canonical)
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
            try await symlinker.link(target: canonical, at: link)
        } else {
            try await symlinker.unlink(at: link, expectedTarget: canonical)
        }
    }
}
