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
        home: URL, installTo: Set<AgentID>
    ) async throws -> Skill {
        let url = URL(string: "https://github.com/\(owner)/\(repo).git")!
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: canonicalBase, withIntermediateDirectories: true)
        let dest = canonicalBase.appendingPathComponent(repo, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            throw SkillportError.fileIO(path: dest, reason: "destination already exists")
        }
        try await git.clone(url: url, to: dest, ref: ref, depth: 1)
        let commitHash = try? await git.headHash(in: dest)
        let identity = SkillIdentity.compute(
            name: repo, source: .github(owner: owner, repo: repo, ref: ref)
        )
        if let commitHash {
            try await cache.set(identity: identity, hash: commitHash)
        }
        let locked = LockedSkill(
            name: repo,
            source: .github(owner: owner, repo: repo, ref: ref),
            installedAt: Date(),
            commitHash: commitHash,
            path: dest
        )
        try await lockFile.upsert(locked)
        var agents: Set<AgentID> = []
        for agentID in installTo {
            try await toggleAgent(name: repo, agent: agentID, install: true, home: home)
            agents.insert(agentID)
        }
        let raw = (try? String(contentsOf: dest.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let parsed = (try? SKILLMdParser.parse(raw)) ?? .init(metadata: SKILLMetadata(), body: raw)
        return Skill(
            name: repo,
            path: dest,
            source: .github(owner: owner, repo: repo, ref: ref),
            frontmatter: parsed.metadata,
            installedAgents: agents,
            updateStatus: .upToDate
        )
    }

    /// Remove from all agents + lockfile. Canonical files are preserved on disk.
    /// Caller can manually delete `~/.agents/skills/<name>/` if they want.
    public func uninstall(name: String, home: URL) async throws {
        let canonical = home.appendingPathComponent(".agents/skills/\(name)")
        // 撤销所有 agent symlinks
        for agent in Agent.defaultAgents(home: home) {
            let link = agent.skillsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: link.path) {
                try? await symlinker.unlink(at: link, expectedTarget: canonical)
            }
        }
        // Remove from lockfile. canonical files intentionally kept on disk.
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
