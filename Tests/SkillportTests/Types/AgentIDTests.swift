import AppKit
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

    @Test("Visual identities use bundled brand icon assets")
    func visualIdentities() {
        var assetNames = Set<String>()
        for id in AgentID.allCases {
            let identity = id.visualIdentity
            #expect(identity.assetName.hasPrefix("agent-"))
            #expect(!identity.assetName.contains("symbol"))
            let url = bundledIconURL(named: identity.assetName)
            #expect(url != nil)
            if let url {
                #expect(NSImage(contentsOf: url) != nil)
            }
            assetNames.insert(identity.assetName)
        }

        #expect(assetNames.count == AgentID.allCases.count)
        #expect(AgentID.claudeCode.visualIdentity.assetName == "agent-claude-code")
        #expect(AgentID.codex.visualIdentity.assetName == "agent-codex")
        #expect(AgentID.gemini.visualIdentity.assetName == "agent-gemini-cli")
    }

    private func bundledIconURL(named assetName: String) -> URL? {
        Bundle.main.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: "AgentIcons"
        ) ?? Bundle.main.url(forResource: assetName, withExtension: "png")
    }

    @Test("Codable round-trip")
    func codable() throws {
        let encoded = try JSONEncoder().encode(AgentID.claudeCode)
        let decoded = try JSONDecoder().decode(AgentID.self, from: encoded)
        #expect(decoded == .claudeCode)
    }
}
