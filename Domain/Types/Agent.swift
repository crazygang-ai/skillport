import Foundation

public struct Agent: Identifiable, Hashable, Sendable {
    public let id: AgentID
    public let skillsDir: URL
    public let fallbackChain: [URL]
    public let isInstalled: Bool

    public init(id: AgentID, skillsDir: URL, fallbackChain: [URL], isInstalled: Bool) {
        self.id = id
        self.skillsDir = skillsDir
        self.fallbackChain = fallbackChain
        self.isInstalled = isInstalled
    }

    /// 根据家目录 URL 构造 11 个 agent 的默认配置。
    /// isInstalled 统一设为 false；实际检测结果应由 `AgentDetector` 合并。
    public static func defaultAgents(home: URL) -> [Agent] {
        func dir(_ relative: String) -> URL {
            home.appendingPathComponent(relative)
        }
        let agentsDir = dir(".agents/skills")
        let claudeDir = dir(".claude/skills")

        return [
            Agent(
                id: .claudeCode,
                skillsDir: dir(".claude/skills"),
                fallbackChain: [],
                isInstalled: false),
            Agent(
                id: .codex,
                skillsDir: dir(".codex/skills"),
                fallbackChain: [agentsDir],
                isInstalled: false),
            Agent(
                id: .gemini,
                skillsDir: dir(".gemini/skills"),
                fallbackChain: [agentsDir],
                isInstalled: false),
            Agent(
                id: .copilot,
                skillsDir: dir(".copilot/skills"),
                fallbackChain: [claudeDir],
                isInstalled: false),
            Agent(
                id: .opencode,
                skillsDir: dir(".config/opencode/skills"),
                fallbackChain: [claudeDir, agentsDir],
                isInstalled: false),
            Agent(
                id: .antigravity,
                skillsDir: dir(".gemini/antigravity/skills"),
                fallbackChain: [],
                isInstalled: false),
            Agent(
                id: .cursor,
                skillsDir: dir(".cursor/skills"),
                fallbackChain: [claudeDir, agentsDir],
                isInstalled: false),
            Agent(
                id: .kiro,
                skillsDir: dir(".kiro/skills"),
                fallbackChain: [],
                isInstalled: false),
            Agent(
                id: .codebuddy,
                skillsDir: dir(".codebuddy/skills"),
                fallbackChain: [],
                isInstalled: false),
            Agent(
                id: .openclaw,
                skillsDir: dir(".openclaw/skills"),
                fallbackChain: [],
                isInstalled: false),
            Agent(
                id: .trae,
                skillsDir: dir(".trae/skills"),
                fallbackChain: [],
                isInstalled: false),
        ]
    }
}
