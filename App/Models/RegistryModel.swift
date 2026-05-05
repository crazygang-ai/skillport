import Foundation
import Observation

@MainActor
@Observable
public final class RegistryModel {
    /// 闭包解耦: 让 model 不必直接依赖整个 SkillManagerActor, 便于测试。
    public typealias InstallHandler =
        @Sendable (
            _ owner: String, _ repo: String, _ ref: String,
            _ skillId: String,
            _ installTo: Set<AgentID>
        ) async throws -> Skill

    public var searchInput: String = "" {
        didSet { scheduleDebouncedSearch() }
    }
    public var category: LeaderboardCategory = .allTime {
        didSet {
            Task { await loadLeaderboard() }
        }
    }
    public var skills: [RegistrySkill] = []
    public var totalCount: Int = 0
    public var selectedID: String?
    public var rendered: RegistryRendered = .empty(reason: "Select a skill")
    public var isLoading: Bool = false
    public var isContentLoading: Bool = false
    public var lastError: String?
    public var selectedAgentsForInstall: Set<AgentID> = []

    private let registry: RegistryActor
    private let contentFetcher: SkillContentFetcher
    private let renderer: RegistryContentRenderer
    private let installHandler: InstallHandler

    private var debounceTask: Task<Void, Never>?
    private var selectionToken: UUID?

    public init(
        registry: RegistryActor,
        contentFetcher: SkillContentFetcher,
        installHandler: @escaping InstallHandler,
        renderer: RegistryContentRenderer = RegistryContentRenderer()
    ) {
        self.registry = registry
        self.contentFetcher = contentFetcher
        self.installHandler = installHandler
        self.renderer = renderer
    }

    public func onAppear() {
        Task { await loadLeaderboard() }
    }

    public func loadLeaderboard() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let result = try await registry.leaderboard(category)
            skills = result.skills
            totalCount = result.totalCount
        } catch {
            lastError = String(describing: error)
            skills = []
            totalCount = 0
        }
    }

    public func runSearchNow() async {
        let q = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            await loadLeaderboard()
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let results = try await registry.search(query: q)
            skills = results
            totalCount = results.count
        } catch {
            lastError = String(describing: error)
            skills = []
        }
    }

    public func select(id: String) async {
        let token = UUID()
        selectionToken = token
        selectedID = id
        rendered = .empty(reason: "Loading…")
        selectedAgentsForInstall = []
        guard let skill = skills.first(where: { $0.id == id }) else {
            isContentLoading = false
            return
        }
        isContentLoading = true
        defer {
            if isCurrentSelection(id: id, token: token) {
                isContentLoading = false
            }
        }
        do {
            let raw = try await contentFetcher.fetchContent(
                source: skill.source, skillId: skill.skillId)
            let next = try renderer.render(raw)
            guard isCurrentSelection(id: id, token: token) else { return }
            rendered = next
        } catch {
            guard isCurrentSelection(id: id, token: token) else { return }
            lastError = String(describing: error)
            rendered = .empty(reason: "Failed to load")
        }
    }

    public func toggleAgentForInstall(_ agent: AgentID) {
        if selectedAgentsForInstall.contains(agent) {
            selectedAgentsForInstall.remove(agent)
        } else {
            selectedAgentsForInstall.insert(agent)
        }
    }

    public func installSelected() async -> Result<Skill, Error> {
        guard let id = selectedID,
            let skill = skills.first(where: { $0.id == id }),
            let (owner, repo) = skill.ownerAndRepo
        else {
            return .failure(SkillportError.unexpected("no registry selection to install"))
        }
        do {
            let installed = try await installHandler(
                owner, repo, "HEAD", skill.skillId, selectedAgentsForInstall)
            return .success(installed)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Debounce

    private func scheduleDebouncedSearch() {
        debounceTask?.cancel()
        let current = searchInput
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.searchInput == current {
                await self.runSearchNow()
            }
        }
    }

    private func isCurrentSelection(id: String, token: UUID) -> Bool {
        selectedID == id && selectionToken == token
    }
}
