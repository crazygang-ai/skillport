import Foundation

public enum AgentAssignmentStatus: Sendable, Equatable, Hashable {
    case direct
    case inherited
    case notAssigned

    public var isAssigned: Bool {
        self != .notAssigned
    }
}

public struct AgentStatus: Sendable, Equatable, Hashable {
    public let binaryOnPath: Bool
    public let configDirExists: Bool
    public let skillsDirExists: Bool
    public let skillCount: Int

    public init(
        binaryOnPath: Bool = false,
        configDirExists: Bool = false,
        skillsDirExists: Bool = false,
        skillCount: Int = 0
    ) {
        self.binaryOnPath = binaryOnPath
        self.configDirExists = configDirExists
        self.skillsDirExists = skillsDirExists
        self.skillCount = skillCount
    }

    /// Any of three signals means the agent is available enough to show in the UI.
    public var isInstalled: Bool {
        binaryOnPath || configDirExists || skillsDirExists
    }

    public static let uninstalled = AgentStatus()
    public static let onPath = AgentStatus(binaryOnPath: true)
}

public struct Agent: Identifiable, Hashable, Sendable {
    public let id: AgentID
    public let skillsDir: URL
    public let fallbackChain: [URL]
    /// Config root (parent of `skillsDir`). E.g. `~/.claude`, `~/.cursor`.
    public let configDir: URL?
    public let status: AgentStatus

    public init(
        id: AgentID,
        skillsDir: URL,
        fallbackChain: [URL],
        configDir: URL? = nil,
        status: AgentStatus = .uninstalled
    ) {
        self.id = id
        self.skillsDir = skillsDir
        self.fallbackChain = fallbackChain
        self.configDir = configDir
        self.status = status
    }

    /// Shorthand used by views that don't care which signal fired.
    public var isInstalled: Bool { status.isInstalled }

    public func assignmentStatus(for skill: Skill) -> AgentAssignmentStatus {
        assignmentStatus(forSkillAt: skill.path)
    }

    public func assignmentStatus(forSkillAt skillPath: URL) -> AgentAssignmentStatus {
        let resolvedSkillPath = skillPath.resolvingSymlinksInPath().path
        let skillName = skillPath.lastPathComponent
        if Self.matches(
            candidate: skillsDir.appendingPathComponent(skillName),
            resolvedSkillPath: resolvedSkillPath
        ) {
            return .direct
        }
        for fallback in fallbackChain {
            if Self.matches(
                candidate: fallback.appendingPathComponent(skillName),
                resolvedSkillPath: resolvedSkillPath
            ) {
                return .inherited
            }
        }
        return .notAssigned
    }

    /// 根据家目录 URL 构造 11 个 agent 的默认配置。
    /// status 统一设为 .uninstalled；实际检测结果由 `AgentDetector` 合并。
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
                configDir: dir(".claude")),
            Agent(
                id: .codex,
                skillsDir: dir(".codex/skills"),
                fallbackChain: [agentsDir],
                configDir: dir(".codex")),
            Agent(
                id: .gemini,
                skillsDir: dir(".gemini/skills"),
                fallbackChain: [agentsDir],
                configDir: dir(".gemini")),
            Agent(
                id: .copilot,
                skillsDir: dir(".copilot/skills"),
                fallbackChain: [claudeDir],
                configDir: dir(".copilot")),
            Agent(
                id: .opencode,
                skillsDir: dir(".config/opencode/skills"),
                fallbackChain: [claudeDir, agentsDir],
                configDir: dir(".config/opencode")),
            Agent(
                id: .antigravity,
                skillsDir: dir(".gemini/antigravity/skills"),
                fallbackChain: [],
                configDir: dir(".gemini")),
            Agent(
                id: .cursor,
                skillsDir: dir(".cursor/skills"),
                fallbackChain: [claudeDir, agentsDir],
                configDir: dir(".cursor")),
            Agent(
                id: .kiro,
                skillsDir: dir(".kiro/skills"),
                fallbackChain: [],
                configDir: dir(".kiro")),
            Agent(
                id: .codebuddy,
                skillsDir: dir(".codebuddy/skills"),
                fallbackChain: [],
                configDir: dir(".codebuddy")),
            Agent(
                id: .openclaw,
                skillsDir: dir(".openclaw/skills"),
                fallbackChain: [],
                configDir: dir(".openclaw")),
            Agent(
                id: .trae,
                skillsDir: dir(".trae/skills"),
                fallbackChain: [],
                configDir: dir(".trae")),
        ]
    }

    private static func matches(candidate: URL, resolvedSkillPath: String) -> Bool {
        let fm = FileManager.default
        if let raw = try? fm.destinationOfSymbolicLink(atPath: candidate.path) {
            let target =
                raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw)
                : candidate.deletingLastPathComponent().appendingPathComponent(raw)
            return target.resolvingSymlinksInPath().path == resolvedSkillPath
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate.resolvingSymlinksInPath().path == resolvedSkillPath
        }
        return false
    }
}
