import Foundation
import Testing

@testable import Skillport

@Suite("AgentID")
struct AgentIDTests {
    @Test("All 11 agents are defined")
    func allCasesCount() {
        #expect(AgentID.allCases.count == 11)
    }

    @Test("Raw values are stable, lowerCamelCase strings")
    func rawValues() {
        #expect(AgentID.claudeCode.rawValue == "claudeCode")
        #expect(AgentID.codex.rawValue == "codex")
        #expect(AgentID.gemini.rawValue == "gemini")
        #expect(AgentID.copilot.rawValue == "copilot")
        #expect(AgentID.opencode.rawValue == "opencode")
        #expect(AgentID.antigravity.rawValue == "antigravity")
        #expect(AgentID.cursor.rawValue == "cursor")
        #expect(AgentID.kiro.rawValue == "kiro")
        #expect(AgentID.codebuddy.rawValue == "codebuddy")
        #expect(AgentID.openclaw.rawValue == "openclaw")
        #expect(AgentID.trae.rawValue == "trae")
    }

    @Test("Binary names use each agent CLI")
    func binaryNames() {
        #expect(AgentID.claudeCode.binaryName == "claude")
        #expect(AgentID.codex.binaryName == "codex")
        #expect(AgentID.copilot.binaryName == "gh")
    }

    @Test("Codable round-trip")
    func codable() throws {
        let encoded = try JSONEncoder().encode(AgentID.claudeCode)
        let decoded = try JSONDecoder().decode(AgentID.self, from: encoded)
        #expect(decoded == .claudeCode)
    }
}
