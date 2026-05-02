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

    @Test("uninstall removes symlink and lockfile entry, keeps canonical files")
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
        let canonical = home.appendingPathComponent(".agents/skills/s/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: canonical.path))  // 保留
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
