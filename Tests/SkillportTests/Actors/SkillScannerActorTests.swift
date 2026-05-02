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
}
