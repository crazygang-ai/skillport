import Foundation
import Observation

public enum SkillOwnershipFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case managed
    case external
}

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
    @ObservationIgnored private var agentRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var agentRefreshQueued = false
    @ObservationIgnored private var agentRefreshNeedsPathRefresh = false

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
        agentRefreshTask?.cancel()
    }

    private func subscribe() {
        subscription = Task { [weak self, manager] in
            let stream = manager.events
            for await event in stream {
                guard let self else { return }
                switch event {
                case .skillsReloaded(let list):
                    self.skills = list
                    self.scheduleAgentRefreshAfterReload()
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
        let strings = AppStrings.current()
        switch error {
        case .invalidLockFile(let reason):
            return strings("Lockfile invalid: \(reason). Continuing without it.")
        case .fileIO(let path, let reason):
            return strings("I/O error at \(path.lastPathComponent): \(reason)")
        case .gitFailed(_, let stderr):
            return strings("git failed: \(stderr)")
        case .networkFailed(_, let reason):
            return strings("Network error: \(reason)")
        case .parseFailed(_, let reason):
            return strings("Parse failed: \(reason)")
        case .keychainFailed(let status):
            return strings("Keychain error: \(status)")
        case .unexpected(let s):
            return s
        }
    }

    public func refresh(forceAgentSearchPathRefresh: Bool = false) async throws {
        isScanning = true
        defer { isScanning = false }
        let refreshedAgentsBeforeScan = !hasDetectedAgents
        if !hasDetectedAgents {
            await refreshAgents(forceSearchPathRefresh: forceAgentSearchPathRefresh)
        }
        let list = try await manager.rescan(home: home)
        skills = list
        if !refreshedAgentsBeforeScan {
            await refreshAgents(forceSearchPathRefresh: forceAgentSearchPathRefresh)
        }
    }

    /// Re-probe which agent CLIs are on PATH without rescanning the filesystem.
    public func refreshAgents(forceSearchPathRefresh: Bool = false) async {
        if forceSearchPathRefresh {
            agentRefreshNeedsPathRefresh = true
        }
        guard !isDetectingAgents else {
            agentRefreshQueued = true
            return
        }
        isDetectingAgents = true
        defer {
            isDetectingAgents = false
            hasDetectedAgents = true
        }
        repeat {
            let shouldRefreshPath = agentRefreshNeedsPathRefresh
            agentRefreshNeedsPathRefresh = false
            agentRefreshQueued = false
            if shouldRefreshPath {
                await detector.invalidateSearchPathCache()
            }
            guard let map = try? await detector.detectAllStatuses(home: home) else { continue }
            agents = Self.agents(home: home, statuses: map)
        } while (agentRefreshQueued || agentRefreshNeedsPathRefresh) && !Task.isCancelled
    }

    public func startWatching() async {
        await manager.startWatching(home: home)
    }

    public func stopWatching() async {
        await manager.stopWatching()
    }

    public func toggle(skillName: String, agent: AgentID, install: Bool) async throws {
        let list = try await manager.toggleAgent(
            name: skillName,
            agent: agent,
            install: install,
            home: home
        )
        skills = list
    }

    public func installLocal(from source: URL, installTo: Set<AgentID>) async throws -> Skill {
        return try await manager.installLocal(from: source, home: home, installTo: installTo)
    }

    public func installGitHub(
        reference: GitHubRepoReference,
        skillId: String?,
        installTo: Set<AgentID>
    ) async throws -> Skill {
        let normalizedSkillId = skillId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try await manager.installGitHub(
            owner: reference.owner,
            repo: reference.repo,
            ref: "HEAD",
            skillId: normalizedSkillId?.isEmpty == true ? nil : normalizedSkillId,
            home: home,
            installTo: installTo
        )
    }

    public func uninstall(name: String) async throws {
        let list = try await manager.uninstall(name: name, home: home)
        skills = list
    }

    @discardableResult
    public func checkAllUpdates() async throws -> [SkillIdentity: UpdateStatus] {
        let results = try await manager.checkAllUpdates(skills: skills)
        applyUpdateStatuses(results)
        return results
    }

    public func applyUpdate(name: String) async throws {
        let list = try await manager.applyUpdate(name: name, home: home)
        skills = list
    }

    public func dismissUpdate(name: String, remoteHash: String) async throws {
        let id = skills.first { $0.name == name }?.id
        try await manager.dismissUpdate(name: name, remoteHash: remoteHash)
        if let id {
            applyUpdateStatus(id: id, status: .upToDate)
        }
    }

    public func skillsFiltered(by agent: AgentID?) -> [Skill] {
        skillsFiltered(by: agent, query: "", ownership: .all)
    }

    public func skillsFiltered(
        by agent: AgentID?,
        query: String,
        ownership: SkillOwnershipFilter
    ) -> [Skill] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return skills.filter { skill in
            if let agent, !skill.installedAgents.contains(agent) {
                return false
            }
            switch ownership {
            case .all:
                break
            case .managed:
                guard skill.isManagedBySkillport else { return false }
            case .external:
                guard !skill.isManagedBySkillport else { return false }
            }
            guard !trimmedQuery.isEmpty else { return true }
            return skill.name.localizedCaseInsensitiveContains(trimmedQuery)
                || (skill.frontmatter.description?.localizedCaseInsensitiveContains(trimmedQuery)
                    ?? false)
        }
    }

    public func skillCount(for agent: AgentID) -> Int {
        skills.filter { $0.installedAgents.contains(agent) }.count
    }

    public func isManagedSkill(_ skill: Skill) -> Bool {
        skill.isManagedBySkillport
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

    private func scheduleAgentRefreshAfterReload() {
        guard !isScanning else { return }
        agentRefreshTask?.cancel()
        agentRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.refreshAgents()
        }
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
