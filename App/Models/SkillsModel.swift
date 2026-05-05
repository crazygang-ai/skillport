import Foundation
import Observation

@MainActor
@Observable
public final class SkillsModel {
    public private(set) var skills: [Skill] = []
    public private(set) var agents: [Agent] = []
    public private(set) var isScanning: Bool = false
    public private(set) var isDetectingAgents: Bool = false
    public private(set) var hasDetectedAgents: Bool = false

    private let manager: SkillManagerActor
    private let detector: AgentDetector
    private let home: URL
    private weak var notifications: NotificationModel?
    @ObservationIgnored private var subscription: Task<Void, Never>?

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
        self.agents = Self.orderedAgents(Agent.defaultAgents(home: home))
        subscribe()
    }

    deinit {
        subscription?.cancel()
    }

    private func subscribe() {
        subscription = Task { [weak self, manager] in
            let stream = manager.events
            for await event in stream {
                guard let self else { return }
                switch event {
                case .skillsReloaded(let list):
                    self.skills = list
                case .skillUpdateStatusChanged(let id, let status):
                    self.applyUpdateStatus(id: id, status: status)
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
        let list = try await manager.rescan(home: home)
        skills = list
    }

    /// Re-probe which agent CLIs are on PATH without rescanning the filesystem.
    public func refreshAgents() async {
        guard !isDetectingAgents else { return }
        isDetectingAgents = true
        defer {
            isDetectingAgents = false
            hasDetectedAgents = true
        }
        guard let map = try? await detector.detectAllStatuses(home: home) else { return }
        agents = Self.agents(home: home, statuses: map)
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

    @discardableResult
    public func checkAllUpdates() async throws -> [SkillIdentity: UpdateStatus] {
        let results = try await manager.checkAllUpdates(skills: skills)
        applyUpdateStatuses(results)
        return results
    }

    public func applyUpdate(name: String) async throws {
        try await manager.applyUpdate(name: name, home: home)
        let list = try await manager.rescan(home: home)
        skills = list
    }

    public func dismissUpdate(name: String, remoteHash: String) async throws {
        try await manager.dismissUpdate(name: name, remoteHash: remoteHash)
        let list = try await manager.rescan(home: home)
        skills = list
    }

    public func skillsFiltered(by agent: AgentID?) -> [Skill] {
        guard let agent else { return skills }
        return skills.filter { $0.installedAgents.contains(agent) }
    }

    public func skillCount(for agent: AgentID) -> Int {
        skills.filter { $0.installedAgents.contains(agent) }.count
    }

    public func isManagedSkill(_ skill: Skill) -> Bool {
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
            .resolvingSymlinksInPath().path
        let skillPath = skill.path.resolvingSymlinksInPath().path
        return skillPath == canonicalBase || skillPath.hasPrefix(canonicalBase + "/")
    }

    private func applyUpdateStatuses(_ statuses: [SkillIdentity: UpdateStatus]) {
        for (id, status) in statuses {
            applyUpdateStatus(id: id, status: status)
        }
    }

    private func applyUpdateStatus(id: SkillIdentity, status: UpdateStatus) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[index].updateStatus = status
    }

    private static func agents(home: URL, statuses: [AgentID: AgentStatus]) -> [Agent] {
        orderedAgents(
            Agent.defaultAgents(home: home).map { a in
                Agent(
                    id: a.id,
                    skillsDir: a.skillsDir,
                    fallbackChain: a.fallbackChain,
                    configDir: a.configDir,
                    status: statuses[a.id] ?? .uninstalled
                )
            }
        )
    }

    private static func orderedAgents(_ agents: [Agent]) -> [Agent] {
        agents.enumerated().sorted { lhs, rhs in
            let lhsAvailable = lhs.element.isInstalled
            let rhsAvailable = rhs.element.isInstalled
            if lhsAvailable != rhsAvailable {
                return lhsAvailable
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
