import Foundation
import Testing

@testable import Skillport

@Suite("SkillScannerActor")
struct SkillScannerActorTests {
    @Test("Scans canonical skills under ~/.agents/skills")
    func scansCanonical() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "beta", description: "b")

        let scanner = SkillScannerActor()
        let skills = try await scanner.scanAll(home: dir.url)
        #expect(skills.count == 2)
        let byName = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) })
        #expect(byName["alpha"]?.frontmatter.description == "demo")
        #expect(byName["beta"]?.frontmatter.description == "b")
    }

    @Test("Detects installed-to-agent via symlink")
    func detectsInstalls() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "x")
        try AgentsFS.installSymlink(home: dir.url, agentRelativeSkillsDir: ".claude/skills", skillName: "x")
        try AgentsFS.installSymlink(home: dir.url, agentRelativeSkillsDir: ".cursor/skills", skillName: "x")

        let scanner = SkillScannerActor()
        let skills = try await scanner.scanAll(home: dir.url)
        #expect(skills.count == 1)
        let x = skills[0]
        #expect(x.installedAgents.contains(.claudeCode))
        #expect(x.installedAgents.contains(.cursor))
        #expect(!x.installedAgents.contains(.kiro))
    }

    @Test("Skips directories without SKILL.md")
    func skipsWithoutSKILLmd() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try dir.mkdir(".agents/skills/empty-dir")
        let scanner = SkillScannerActor()
        let skills = try await scanner.scanAll(home: dir.url)
        #expect(skills.isEmpty)
    }

    @Test("Throws when canonical skills store cannot be listed")
    func canonicalStoreListErrorThrows() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent(".agents"),
            withIntermediateDirectories: true
        )
        try "not a directory".write(
            to: dir.url.appendingPathComponent(".agents/skills"),
            atomically: true,
            encoding: .utf8
        )

        let scanner = SkillScannerActor()
        await #expect(throws: SkillportError.self) {
            _ = try await scanner.scanAll(home: dir.url)
        }
    }

    @Test("Inherited fallback: codex sees .agents/skills entries without symlink")
    func inheritedFallback() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        // Skill exists only in canonical .agents/skills; no symlink under .codex/skills.
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "shared")

        let scanner = SkillScannerActor()
        let skills = try await scanner.scanAll(home: dir.url)
        #expect(skills.count == 1)
        let s = skills[0]
        // codex / gemini / cursor / opencode / copilot 都应通过 fallback 继承到
        #expect(s.installedAgents.contains(.codex))
        #expect(s.installedAgents.contains(.gemini))
        #expect(s.installedAgents.contains(.cursor))
        #expect(s.installedAgents.contains(.opencode))
        // claudeCode 没有 fallback，不应继承
        #expect(!s.installedAgents.contains(.claudeCode))
        // kiro 也没 fallback
        #expect(!s.installedAgents.contains(.kiro))
    }

    @Test("Picks up foreign skill that lives only in an agent dir")
    func foreignSkillInAgentDir() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        // Skill only in .claude/skills/foo — no canonical copy.
        try AgentsFS.createForeignSkill(
            in: dir.url, agentRelativeSkillsDir: ".claude/skills", name: "foo")

        let scanner = SkillScannerActor()
        let skills = try await scanner.scanAll(home: dir.url)
        #expect(skills.count == 1)
        let foo = skills[0]
        #expect(foo.name == "foo")
        #expect(foo.installedAgents.contains(.claudeCode))
        // copilot 的 fallback 链包含 .claude/skills，应被继承识别
        #expect(foo.installedAgents.contains(.copilot))
    }
}
