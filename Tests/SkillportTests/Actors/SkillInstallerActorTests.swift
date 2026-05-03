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
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillpilot-cache.json"))
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
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillpilot-cache.json"))
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
            cache: CommitHashCache(path: home.appendingPathComponent(".agents/.skillpilot-cache.json"))
        )
        _ = try await installer.installLocal(from: src, home: home, installTo: [])
        try await installer.toggleAgent(name: "t", agent: .cursor, install: true, home: home)
        let link = home.appendingPathComponent(".cursor/skills/t")
        #expect(FileManager.default.fileExists(atPath: link.path))
        try await installer.toggleAgent(name: "t", agent: .cursor, install: false, home: home)
        #expect(!FileManager.default.fileExists(atPath: link.path))
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

    private func makeInstaller(home: URL) -> SkillInstallerActor {
        SkillInstallerActor(
            git: GitActor(),
            symlinker: SymlinkManagerActor(),
            lockFile: LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json")),
            cache: CommitHashCache(
                path: home.appendingPathComponent(".agents/.skillpilot-cache.json"))
        )
    }
}
