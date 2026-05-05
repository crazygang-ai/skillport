import Foundation
import Testing

@testable import Skillport

@Suite("SkillInstallerActor")
struct SkillInstallerActorTests {
    @Test("installLocal creates canonical copy + lockfile entry")
    func installLocal() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("localSkill")
        try "---\ndescription: t\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")

        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: lockPath),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )
        let skill = try await installer.installLocal(from: src, home: home, installTo: [.claudeCode])
        #expect(skill.name == "localSkill")
        #expect(skill.installedAgents.contains(.claudeCode))

        // lockfile 应含新条目
        let lock = try LockFile.decode(from: Data(contentsOf: lockPath))
        #expect(lock.skills.contains { $0.name == "localSkill" })
        // 对应 agent 目录应存在 symlink
        let link = home.appendingPathComponent(".claude/skills/localSkill")
        let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(resolved.hasSuffix(".agents/skills/localSkill"))
    }

    @Test("uninstall removes symlink, lockfile entry, and canonical files")
    func uninstall() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("s")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")

        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: lockPath),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )
        _ = try await installer.installLocal(from: src, home: home, installTo: [.kiro])
        try await installer.uninstall(name: "s", home: home)
        let link = home.appendingPathComponent(".kiro/skills/s")
        #expect(!FileManager.default.fileExists(atPath: link.path))
        let canonicalDir = home.appendingPathComponent(".agents/skills/s")
        #expect(!FileManager.default.fileExists(atPath: canonicalDir.path))  // 完全删除
        let lock = try LockFile.decode(from: Data(contentsOf: lockPath))
        #expect(lock.skills.isEmpty)
    }

    @Test("toggleAgent creates or removes symlink without touching lockfile entry")
    func toggleAgent() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("t")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json")),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )
        _ = try await installer.installLocal(from: src, home: home, installTo: [])
        // Use .kiro — no fallback chain, so toggleAgent must create an actual symlink.
        try await installer.toggleAgent(name: "t", agent: .kiro, install: true, home: home)
        let link = home.appendingPathComponent(".kiro/skills/t")
        #expect(FileManager.default.fileExists(atPath: link.path))
        try await installer.toggleAgent(name: "t", agent: .kiro, install: false, home: home)
        #expect(!FileManager.default.fileExists(atPath: link.path))
    }

    @Test("toggle-off does not delete same-name real agent-local directory")
    func toggleOffLeavesUserDirectory() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("user-owned")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json")),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )
        _ = try await installer.installLocal(from: src, home: home, installTo: [])
        let userDir = home.appendingPathComponent(".kiro/skills/user-owned")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "do not delete".write(
            to: userDir.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await installer.toggleAgent(name: "user-owned", agent: .kiro, install: false, home: home)

        #expect(FileManager.default.fileExists(atPath: userDir.appendingPathComponent("note.txt").path))
    }

    @Test("installLocal rolls back canonical copy and lockfile when agent install fails")
    func installLocalRollsBackOnAgentFailure() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("rollback-local")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let blockingUserDir = home.appendingPathComponent(".kiro/skills/rollback-local")
        try FileManager.default.createDirectory(at: blockingUserDir, withIntermediateDirectories: true)

        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: lockPath),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )

        await #expect(throws: SkillportError.self) {
            _ = try await installer.installLocal(from: src, home: home, installTo: [.kiro])
        }

        let canonical = home.appendingPathComponent(".agents/skills/rollback-local")
        #expect(!FileManager.default.fileExists(atPath: canonical.path))
        #expect(FileManager.default.fileExists(atPath: blockingUserDir.path))
        let lock = try LockFile.decode(from: Data(contentsOf: lockPath))
        #expect(lock.skills.isEmpty)
    }

    @Test("uninstall removes canonical and managed symlink but leaves same-name real agent-local directory")
    func uninstallLeavesUserDirectory() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("safe-uninstall")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json")),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )
        _ = try await installer.installLocal(from: src, home: home, installTo: [.kiro])
        let managedLink = home.appendingPathComponent(".kiro/skills/safe-uninstall")
        #expect(FileManager.default.fileExists(atPath: managedLink.path))

        let userDir = home.appendingPathComponent(".claude/skills/safe-uninstall")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "mine".write(
            to: userDir.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await installer.uninstall(name: "safe-uninstall", home: home)

        #expect(!FileManager.default.fileExists(atPath: managedLink.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: home.appendingPathComponent(".agents/skills/safe-uninstall").path))
        #expect(FileManager.default.fileExists(atPath: userDir.appendingPathComponent("note.txt").path))
    }
}

@Suite("SkillInstallerActor — multi-skill repos", .serialized)
struct SkillInstallerMultiSkillTests {
    @Test("installGitHub with skillId == repo uses single-skill path")
    func singleSkillDefaultBehavior() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)

        let installer = makeInstaller(home: home)
        let skill = try await installer.installGitHub(
            sourceURL: bareRepo,
            owner: "test", repo: "example", ref: "HEAD",
            skillId: "example",
            home: home, installTo: []
        )
        #expect(skill.name == "example")
        let canonical = home.appendingPathComponent(".agents/skills/example")
        #expect(
            FileManager.default.fileExists(
                atPath: canonical.appendingPathComponent("SKILL.md").path))
    }

    @Test("installGitHub with skillId differing from repo extracts subdir")
    func multiSkillSubdirExtraction() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["sub1", "sub2"])

        let installer = makeInstaller(home: home)
        let skill = try await installer.installGitHub(
            sourceURL: bareRepo,
            owner: "test", repo: "example", ref: "HEAD",
            skillId: "sub1",
            home: home, installTo: []
        )
        #expect(skill.name == "sub1")

        let canonical = home.appendingPathComponent(".agents/skills/sub1")
        #expect(
            FileManager.default.fileExists(
                atPath: canonical.appendingPathComponent("SKILL.md").path))

        let sub2 = home.appendingPathComponent(".agents/skills/sub2")
        #expect(!FileManager.default.fileExists(atPath: sub2.path))
    }

    @Test("installGitHub with non-existent skillId throws")
    func multiSkillMissingSubdir() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["sub1"])

        let installer = makeInstaller(home: home)
        await #expect(throws: SkillportError.self) {
            _ = try await installer.installGitHub(
                sourceURL: bareRepo,
                owner: "test", repo: "example", ref: "HEAD",
                skillId: "does-not-exist",
                home: home, installTo: []
            )
        }
    }

    @Test("installGitHub is idempotent: repeat install overwrites dest")
    func installIdempotentReplacesDest() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)

        let installer = makeInstaller(home: home)
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "example", home: home, installTo: [])
        // Second install must not throw.
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "example", home: home, installTo: [])
        let canonical = home.appendingPathComponent(".agents/skills/example")
        #expect(FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))
    }

    @Test("installGitHub records skillFolderHash and skillPath in lockfile for multi-skill repo")
    func installRecordsFolderHashAndPath() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["sub1"])

        let installer = makeInstaller(home: home)
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "sub1", home: home, installTo: [])
        let lock = try LockFile.decode(from: Data(contentsOf: lockPath))
        let entry = lock.skills.first { $0.name == "sub1" }
        #expect(entry != nil)
        #expect(entry?.skillPath == "skills/sub1")
        #expect(entry?.skillFolderHash != nil)
        #expect((entry?.skillFolderHash?.count ?? 0) == 40)
    }

    @Test("installGitHub copy failure preserves existing canonical skill")
    func installGitHubCopyFailurePreservesExistingCanonical() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let canonical = try oldCanonicalSkill(home: home, name: "example")
        let bareRepo = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)
        let installer = makeInstaller(
            home: home,
            directoryCopy: { _, _, _ in
                throw SkillportError.fileIO(path: canonical, reason: "simulated copy failure")
            }
        )

        await #expect(throws: SkillportError.self) {
            _ = try await installer.installGitHub(
                sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
                skillId: "example", home: home, installTo: [])
        }

        #expect(try skillBody(at: canonical) == "old")
    }

    @Test("installGitHub locate failure preserves existing canonical skill")
    func installGitHubLocateFailurePreservesExistingCanonical() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let canonical = try oldCanonicalSkill(home: home, name: "missing")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["other"])
        let installer = makeInstaller(home: home)

        await #expect(throws: SkillportError.self) {
            _ = try await installer.installGitHub(
                sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
                skillId: "missing", home: home, installTo: [])
        }

        #expect(try skillBody(at: canonical) == "old")
    }

    @Test("installGitHub rejects remote source trees containing symlinks")
    func installGitHubRejectsSymlinkTree() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithRootSKILLSymlink(under: dir.url)
        let installer = makeInstaller(home: home)

        await #expect(throws: SkillportError.self) {
            _ = try await installer.installGitHub(
                sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
                skillId: "example", home: home, installTo: [])
        }

        let canonical = home.appendingPathComponent(".agents/skills/example")
        #expect(!FileManager.default.fileExists(atPath: canonical.path))
    }

    @Test("installGitHub post-swap agent failure rolls back existing canonical skill")
    func installGitHubPostSwapFailureRollsBackCanonical() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let canonical = try oldCanonicalSkill(home: home, name: "example")
        let bareRepo = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)
        let blockingUserDir = home.appendingPathComponent(".kiro/skills/example")
        try FileManager.default.createDirectory(at: blockingUserDir, withIntermediateDirectories: true)
        let installer = makeInstaller(home: home)

        await #expect(throws: SkillportError.self) {
            _ = try await installer.installGitHub(
                sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
                skillId: "example", home: home, installTo: [.kiro])
        }

        #expect(try skillBody(at: canonical) == "old")
        #expect(FileManager.default.fileExists(atPath: blockingUserDir.path))
    }

    @Test("toggleAgent skips symlink when fallback chain already grants access")
    func toggleSkipsInheritedAgent() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("inheritSkill")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let installer = SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json")),
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillport-cache.json"))
        )
        _ = try await installer.installLocal(from: src, home: home, installTo: [])
        // .cursor fallbackChain 包含 .agents/skills；canonical 就在 .agents/skills/inheritSkill
        // 所以 cursor 可以通过 fallback 读到，无需额外 symlink。
        try await installer.toggleAgent(
            name: "inheritSkill", agent: .cursor, install: true, home: home)
        let link = home.appendingPathComponent(".cursor/skills/inheritSkill")
        #expect(!FileManager.default.fileExists(atPath: link.path))
    }

    @Test("uninstall after multi-skill install removes the correct canonical dir")
    func uninstallMultiSkill() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["alpha", "beta"])

        let installer = makeInstaller(home: home)
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "r", ref: "HEAD",
            skillId: "alpha", home: home, installTo: [])
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "r", ref: "HEAD",
            skillId: "beta", home: home, installTo: [])

        try await installer.uninstall(name: "alpha", home: home)

        let alpha = home.appendingPathComponent(".agents/skills/alpha")
        let beta = home.appendingPathComponent(".agents/skills/beta")
        #expect(!FileManager.default.fileExists(atPath: alpha.path))
        #expect(FileManager.default.fileExists(atPath: beta.path))
    }

    private func makeInstaller(
        home: URL,
        directoryCopy: @escaping SkillInstallerActor.DirectoryCopy = { src, dest, excludes in
            try SkillInstallerActor.copyDirectory(from: src, to: dest, excluding: excludes)
        }
    ) -> SkillInstallerActor {
        SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json")),
            cache: CommitHashCache(
                path: home.appendingPathComponent(".agents/.skillport-cache.json")),
            directoryCopy: directoryCopy
        )
    }

    @discardableResult
    private func oldCanonicalSkill(home: URL, name: String) throws -> URL {
        let canonical = home.appendingPathComponent(".agents/skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try "---\n---\nold".write(
            to: canonical.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        return canonical
    }

    private func skillBody(at canonical: URL) throws -> String {
        let raw = try String(contentsOf: canonical.appendingPathComponent("SKILL.md"), encoding: .utf8)
        return raw.components(separatedBy: "---").last?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? raw
    }
}
