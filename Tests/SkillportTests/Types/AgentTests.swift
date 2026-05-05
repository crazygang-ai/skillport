import Foundation
import Testing

@testable import Skillport

@Suite("Agent")
struct AgentTests {
    @Test("Default agents() returns all 11 with correct skills directories")
    func defaultAgents() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let agents = Agent.defaultAgents(home: home)
        #expect(agents.count == 11)
        let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        #expect(byID[.claudeCode]?.skillsDir == home.appendingPathComponent(".claude/skills"))
        #expect(byID[.codex]?.skillsDir == home.appendingPathComponent(".codex/skills"))
        #expect(byID[.gemini]?.skillsDir == home.appendingPathComponent(".gemini/skills"))
        #expect(byID[.copilot]?.skillsDir == home.appendingPathComponent(".copilot/skills"))
        #expect(byID[.opencode]?.skillsDir == home.appendingPathComponent(".config/opencode/skills"))
        #expect(byID[.antigravity]?.skillsDir == home.appendingPathComponent(".gemini/antigravity/skills"))
        #expect(byID[.cursor]?.skillsDir == home.appendingPathComponent(".cursor/skills"))
        #expect(byID[.kiro]?.skillsDir == home.appendingPathComponent(".kiro/skills"))
        #expect(byID[.codebuddy]?.skillsDir == home.appendingPathComponent(".codebuddy/skills"))
        #expect(byID[.openclaw]?.skillsDir == home.appendingPathComponent(".openclaw/skills"))
        #expect(byID[.trae]?.skillsDir == home.appendingPathComponent(".trae/skills"))
    }

    @Test("Fallback chain matches README spec for agents with secondary sources")
    func fallbackChain() {
        let home = URL(fileURLWithPath: "/tmp/testhome")
        let agents = Agent.defaultAgents(home: home)
        let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        // Claude Code / Kiro / CodeBuddy / Antigravity / OpenClaw / Trae: 仅自己目录
        #expect(byID[.claudeCode]?.fallbackChain.isEmpty == true)
        #expect(byID[.kiro]?.fallbackChain.isEmpty == true)
        #expect(byID[.codebuddy]?.fallbackChain.isEmpty == true)

        // Codex: own → ~/.agents/skills
        #expect(byID[.codex]?.fallbackChain == [home.appendingPathComponent(".agents/skills")])
        // Gemini: own → ~/.agents/skills
        #expect(byID[.gemini]?.fallbackChain == [home.appendingPathComponent(".agents/skills")])
        // Copilot: own → ~/.claude/skills
        #expect(byID[.copilot]?.fallbackChain == [home.appendingPathComponent(".claude/skills")])
        // OpenCode: own → ~/.claude/skills → ~/.agents/skills
        #expect(
            byID[.opencode]?.fallbackChain == [
                home.appendingPathComponent(".claude/skills"),
                home.appendingPathComponent(".agents/skills"),
            ])
        // Cursor: own → ~/.claude/skills → ~/.agents/skills
        #expect(
            byID[.cursor]?.fallbackChain == [
                home.appendingPathComponent(".claude/skills"),
                home.appendingPathComponent(".agents/skills"),
            ])
    }

    @Test("assignmentStatus distinguishes direct, inherited, and not assigned")
    func assignmentStatus() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let skill = try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        try AgentsFS.installSymlink(
            home: dir.url,
            agentRelativeSkillsDir: ".claude/skills",
            skillName: "alpha"
        )
        let agents = Agent.defaultAgents(home: dir.url)
        let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        #expect(byID[.claudeCode]?.assignmentStatus(forSkillAt: skill) == .direct)
        #expect(byID[.codex]?.assignmentStatus(forSkillAt: skill) == .inherited)
        #expect(byID[.kiro]?.assignmentStatus(forSkillAt: skill) == .notAssigned)
    }
}
