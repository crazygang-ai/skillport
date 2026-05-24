import Foundation

public enum AgentID: String, CaseIterable, Codable, Hashable, Sendable {
    case claudeCode
    case codex
    case gemini
    case copilot
    case opencode
    case antigravity
    case cursor
    case kiro
    case codebuddy
    case openclaw
    case trae
}

public struct AgentVisualIdentity: Sendable, Equatable {
    public let assetName: String
    public let fallbackInitials: String

    public init(assetName: String, fallbackInitials: String) {
        self.assetName = assetName
        self.fallbackInitials = fallbackInitials
    }
}

extension AgentID {
    /// UI 展示名称。
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .copilot: return "Copilot CLI"
        case .opencode: return "OpenCode"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        case .kiro: return "Kiro"
        case .codebuddy: return "CodeBuddy"
        case .openclaw: return "OpenClaw"
        case .trae: return "Trae"
        }
    }

    /// 用于检测 agent 是否安装的命令名。
    public var binaryName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .copilot: return "gh"
        case .opencode: return "opencode"
        case .antigravity: return "antigravity"
        case .cursor: return "cursor"
        case .kiro: return "kiro"
        case .codebuddy: return "codebuddy"
        case .openclaw: return "openclaw"
        case .trae: return "trae"
        }
    }

    /// Shared visual identity for agent-facing UI surfaces.
    public var visualIdentity: AgentVisualIdentity {
        switch self {
        case .claudeCode:
            AgentVisualIdentity(assetName: "agent-claude-code", fallbackInitials: "CC")
        case .codex:
            AgentVisualIdentity(assetName: "agent-codex", fallbackInitials: "CX")
        case .gemini:
            AgentVisualIdentity(assetName: "agent-gemini-cli", fallbackInitials: "GM")
        case .copilot:
            AgentVisualIdentity(assetName: "agent-copilot", fallbackInitials: "CP")
        case .opencode:
            AgentVisualIdentity(assetName: "agent-opencode", fallbackInitials: "OC")
        case .antigravity:
            AgentVisualIdentity(assetName: "agent-antigravity", fallbackInitials: "AG")
        case .cursor:
            AgentVisualIdentity(assetName: "agent-cursor", fallbackInitials: "CU")
        case .kiro:
            AgentVisualIdentity(assetName: "agent-kiro", fallbackInitials: "KI")
        case .codebuddy:
            AgentVisualIdentity(assetName: "agent-codebuddy", fallbackInitials: "CB")
        case .openclaw:
            AgentVisualIdentity(assetName: "agent-openclaw", fallbackInitials: "OW")
        case .trae:
            AgentVisualIdentity(assetName: "agent-trae", fallbackInitials: "TR")
        }
    }
}
