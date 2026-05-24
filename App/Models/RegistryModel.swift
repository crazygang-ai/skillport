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
            if trimmedSearchInput.isEmpty {
                Task { await loadLeaderboard() }
            }
        }
    }
    public var skills: [RegistrySkill] = []
    public var totalCount: Int = 0
    public var selectedID: String?
    public var rendered: RegistryRendered = .empty(reason: "Select a skill")
    public var isLoading: Bool = false
    public var isContentLoading: Bool = false
    public var listError: String?
    public var contentError: String?
    public var selectedAgentsForInstall: Set<AgentID> = []

    private let registry: RegistryActor
    private let contentFetcher: SkillContentFetcher
    private let renderer: RegistryContentRenderer
    private let installHandler: InstallHandler

    private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    private var selectionToken: UUID?
    private var listToken: UUID?

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
        let token = beginListRequest()
        let requestedCategory = category
        isLoading = true
        listError = nil
        defer { finishListRequest(token) }
        do {
            let result = try await registry.leaderboard(requestedCategory)
            guard isCurrentListRequest(token),
                category == requestedCategory,
                trimmedSearchInput.isEmpty
            else { return }
            skills = result.skills
            totalCount = result.totalCount
        } catch {
            guard isCurrentListRequest(token),
                category == requestedCategory,
                trimmedSearchInput.isEmpty
            else { return }
            listError = String(describing: error)
            skills = []
            totalCount = 0
        }
    }

    public func runSearchNow() async {
        let q = trimmedSearchInput
        guard !q.isEmpty else {
            await loadLeaderboard()
            return
        }
        let token = beginListRequest()
        isLoading = true
        listError = nil
        defer { finishListRequest(token) }
        do {
            let results = try await registry.search(query: q)
            guard isCurrentListRequest(token), trimmedSearchInput == q else { return }
            skills = results
            totalCount = results.count
        } catch {
            guard isCurrentListRequest(token), trimmedSearchInput == q else { return }
            listError = String(describing: error)
            skills = []
        }
    }

    public func select(id: String) async {
        let task = beginSelect(id: id)
        await task?.value
    }

    @discardableResult
    public func beginSelect(id: String) -> Task<Void, Never>? {
        selectionTask?.cancel()
        let token = UUID()
        selectionToken = token
        selectedID = id
        rendered = .empty(reason: "Loading…")
        contentError = nil
        selectedAgentsForInstall = []
        guard let skill = skills.first(where: { $0.id == id }) else {
            isContentLoading = false
            return nil
        }
        isContentLoading = true

        let task = Task { [weak self, contentFetcher, renderer] in
            do {
                let raw = try await contentFetcher.fetchContent(
                    source: skill.source, skillId: skill.skillId)
                guard !Task.isCancelled else { return }
                let next = try await renderer.render(raw)
                guard !Task.isCancelled else { return }
                self?.finishSelection(id: id, token: token, rendered: next)
            } catch is CancellationError {
                self?.finishCancelledSelection(id: id, token: token)
            } catch {
                self?.failSelection(id: id, token: token, error: error)
            }
        }
        selectionTask = task
        return task
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

    private func finishSelection(
        id: String,
        token: UUID,
        rendered next: RegistryRendered
    ) {
        guard isCurrentSelection(id: id, token: token) else { return }
        rendered = next
        isContentLoading = false
    }

    private func failSelection(id: String, token: UUID, error: Error) {
        guard isCurrentSelection(id: id, token: token) else { return }
        contentError = String(describing: error)
        rendered = .empty(reason: "Documentation unavailable")
        isContentLoading = false
    }

    private func finishCancelledSelection(id: String, token: UUID) {
        guard isCurrentSelection(id: id, token: token) else { return }
        isContentLoading = false
    }

    private var trimmedSearchInput: String {
        searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginListRequest() -> UUID {
        let token = UUID()
        listToken = token
        return token
    }

    private func isCurrentListRequest(_ token: UUID) -> Bool {
        listToken == token
    }

    private func finishListRequest(_ token: UUID) {
        guard isCurrentListRequest(token) else { return }
        isLoading = false
    }
}
