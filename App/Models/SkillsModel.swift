import Foundation
import Observation

@MainActor
@Observable
public final class SkillsModel {
    public private(set) var skills: [Skill] = []
    public private(set) var agents: [Agent] = []
    public private(set) var isScanning: Bool = false

    private let manager: SkillManagerActor
    private let home: URL
    nonisolated(unsafe) private var subscription: Task<Void, Never>?

    public init(manager: SkillManagerActor, home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.manager = manager
        self.home = home
        self.agents = Agent.defaultAgents(home: home)
        subscribe()
    }

    nonisolated deinit {
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
                default:
                    continue
                }
            }
        }
    }

    public func refresh() async throws {
        isScanning = true
        defer { isScanning = false }
        let list = try await manager.rescan(home: home)
        skills = list
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
