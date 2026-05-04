import Foundation
import Observation

@MainActor
@Observable
public final class SkillsModel {
    public private(set) var skills: [Skill] = []
    public private(set) var agents: [Agent] = []
    public private(set) var isScanning: Bool = false

    private let manager: SkillManagerActor
    private let detector: AgentDetector
    private let home: URL
    private weak var notifications: NotificationModel?
    nonisolated(unsafe) private var subscription: Task<Void, Never>?

    public init(
        manager: SkillManagerActor,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        detector: AgentDetector = AgentDetector(),
        notifications: NotificationModel? = nil
    ) {
        self.manager = manager
        self.home = home
        self.detector = detector
        self.notifications = notifications
        self.agents = Agent.defaultAgents(home: home)
        subscribe()
    }

    deinit {
        subscription?.cancel()
    }

    private func subscribe() {
        subscription = Task { [weak self, manager] in
            let stream = await manager.events
            for await event in stream {
                guard let self else { return }
                switch event {
                case .skillsReloaded(let list):
                    self.skills = list
                case .error(let err):
                    self.notifications?.post(.init(level: .error, message: Self.message(for: err)))
                default:
                    continue
                }
            }
        }
    }

    private static func message(for error: SkillportError) -> String {
        switch error {
        case .invalidLockFile(let reason):
            return String(localized: "Lockfile invalid: \(reason). Continuing without it.")
        case .fileIO(let path, let reason):
            return String(localized: "I/O error at \(path.lastPathComponent): \(reason)")
        case .gitFailed(_, let stderr):
            return String(localized: "git failed: \(stderr)")
        case .networkFailed(_, let reason):
            return String(localized: "Network error: \(reason)")
        case .parseFailed(_, let reason):
            return String(localized: "Parse failed: \(reason)")
        case .keychainFailed(let status):
            return String(localized: "Keychain error: \(status)")
        case .unexpected(let s):
            return s
        }
    }

    public func refresh() async throws {
        isScanning = true
        defer { isScanning = false }
        async let detected = try? detector.detectAllStatuses(home: home)
        let list = try await manager.rescan(home: home)
        skills = list
        if let map = await detected {
            agents = Agent.defaultAgents(home: home).map { a in
                Agent(
                    id: a.id,
                    skillsDir: a.skillsDir,
                    fallbackChain: a.fallbackChain,
                    configDir: a.configDir,
                    status: map[a.id] ?? .uninstalled
                )
            }
        }
    }

    /// Re-probe which agent CLIs are on PATH without rescanning the filesystem.
    public func refreshAgents() async {
        guard let map = try? await detector.detectAllStatuses(home: home) else { return }
        agents = Agent.defaultAgents(home: home).map { a in
            Agent(
                id: a.id,
                skillsDir: a.skillsDir,
                fallbackChain: a.fallbackChain,
                configDir: a.configDir,
                status: map[a.id] ?? .uninstalled
            )
        }
    }

    public func startWatching() async {
        await manager.startWatching(home: home)
    }

    public func stopWatching() async {
        await manager.stopWatching()
    }

    public func toggle(skillName: String, agent: AgentID, install: Bool) async throws {
        try await manager.toggleAgent(name: skillName, agent: agent, install: install, home: home)
        // Re-scan directly to get deterministic state (stream propagation is async).
        let list = try await manager.rescan(home: home)
        skills = list
    }

    public func installLocal(from source: URL, installTo: Set<AgentID>) async throws -> Skill {
        return try await manager.installLocal(from: source, home: home, installTo: installTo)
    }

    public func uninstall(name: String) async throws {
        try await manager.uninstall(name: name, home: home)
    }

    public func skillsFiltered(by agent: AgentID?) -> [Skill] {
        guard let agent else { return skills }
        return skills.filter { $0.installedAgents.contains(agent) }
    }
}
