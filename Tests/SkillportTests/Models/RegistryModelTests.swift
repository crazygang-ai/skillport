import Foundation
import Testing

@testable import Skillport

@MainActor
@Suite("RegistryModel", .serialized)
struct RegistryModelTests {
    private func makeModel() -> RegistryModel {
        MockURLProtocol.resetSync()
        let session = MockURLProtocol.makeSession()
        let registry = RegistryActor(session: session)
        let fetcher = SkillContentFetcher(session: session)
        // Install handler stubbed — tests that exercise install go to T11 E2E.
        let installer: RegistryModel.InstallHandler = { _, _, _, _, _ in
            throw SkillportError.unexpected("install not stubbed for this test")
        }
        return RegistryModel(
            registry: registry,
            contentFetcher: fetcher,
            installHandler: installer
        )
    }

    @Test("initial state is .allTime with no selection")
    func initialState() async {
        let model = makeModel()
        #expect(model.category == .allTime)
        #expect(model.searchInput.isEmpty)
        #expect(model.skills.isEmpty)
        #expect(model.selectedID == nil)
    }

    @Test("loadLeaderboard populates skills + totalCount")
    func loadLeaderboard() async throws {
        let model = makeModel()
        let fixtureURL = try #require(
            TestBundleLocator.bundle.url(
                forResource: "skills-sh-leaderboard-alltime", withExtension: "html"))
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/")!, status: 200,
            body: Data(html.utf8))
        await model.loadLeaderboard()
        #expect(model.skills.count > 0)
        #expect(model.isLoading == false)
    }

    @Test("select(id:) triggers content fetch and populates rendered")
    func selectFetchesContent() async throws {
        let model = makeModel()
        model.skills = [
            RegistrySkill(id: "a/b/b", skillId: "b", name: "B", installs: 1, source: "a/b")
        ]
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 200,
            body: Data("# doc from fixture".utf8)
        )
        await model.select(id: "a/b/b")
        #expect(model.selectedID == "a/b/b")
        switch model.rendered {
        case .markdown(let s):
            #expect(String(s.characters).contains("doc from fixture"))
        default:
            Issue.record("expected .markdown rendered result, got \(model.rendered)")
        }
    }

    @Test("select(id:) ignores stale slower content response")
    func selectRaceKeepsCurrentSelection() async throws {
        let model = makeModel()
        model.skills = [
            RegistrySkill(id: "owner/a/a", skillId: "a", name: "A", installs: 1, source: "owner/a"),
            RegistrySkill(id: "owner/b/b", skillId: "b", name: "B", installs: 1, source: "owner/b"),
        ]
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            handler: { request in
                let path = request.url?.path ?? ""
                if path.contains("/owner/a/") {
                    Thread.sleep(forTimeInterval: 0.25)
                    return .init(statusCode: 200, headers: [:], body: Data("# A body".utf8))
                }
                return .init(statusCode: 200, headers: [:], body: Data("# B body".utf8))
            }
        )

        let first = Task { await model.select(id: "owner/a/a") }
        try await Task.sleep(nanoseconds: 50_000_000)
        await model.select(id: "owner/b/b")
        await first.value

        #expect(model.selectedID == "owner/b/b")
        switch model.rendered {
        case .markdown(let s):
            #expect(String(s.characters).contains("B body"))
        default:
            Issue.record("expected .markdown rendered result, got \(model.rendered)")
        }
    }

    @Test("runSearchNow hits /api/search and populates skills")
    func searchFiresNetwork() async throws {
        let model = makeModel()
        let json = #"{"skills":[{"id":"x/y/y","skillId":"y","name":"y","installs":1,"source":"x/y"}]}"#
        MockURLProtocol.stub(
            urlMatch: { $0.path == "/api/search" },
            status: 200,
            body: Data(json.utf8)
        )
        model.searchInput = "y"
        await model.runSearchNow()
        #expect(model.skills.count == 1)
        #expect(model.skills[0].skillId == "y")
    }

    @Test("slow leaderboard response does not overwrite newer search results")
    func slowLeaderboardDoesNotOverwriteSearch() async throws {
        let model = makeModel()
        let fixtureURL = try #require(
            TestBundleLocator.bundle.url(
                forResource: "skills-sh-leaderboard-alltime", withExtension: "html"))
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        await MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/")!,
            handler: { _ in
                Thread.sleep(forTimeInterval: 0.25)
                return .init(statusCode: 200, headers: [:], body: Data(html.utf8))
            }
        )
        let json =
            #"{"skills":[{"id":"owner/needle/needle","skillId":"needle","name":"needle","installs":1,"source":"owner/needle"}]}"#
        MockURLProtocol.stub(
            urlMatch: { $0.path == "/api/search" },
            status: 200,
            body: Data(json.utf8)
        )

        let leaderboard = Task { await model.loadLeaderboard() }
        try await Task.sleep(nanoseconds: 50_000_000)
        model.searchInput = "needle"
        await model.runSearchNow()
        await leaderboard.value

        #expect(model.skills.count == 1)
        #expect(model.skills.first?.skillId == "needle")
        #expect(model.totalCount == 1)
    }

    @Test("slow search response does not overwrite newer search results")
    func slowSearchDoesNotOverwriteNewerSearch() async throws {
        let model = makeModel()
        MockURLProtocol.stub(
            urlMatch: { $0.path == "/api/search" },
            handler: { request in
                let query = request.url?.query ?? ""
                if query.contains("slow") {
                    Thread.sleep(forTimeInterval: 0.25)
                    let json =
                        #"{"skills":[{"id":"owner/slow/slow","skillId":"slow","name":"slow","installs":1,"source":"owner/slow"}]}"#
                    return .init(statusCode: 200, headers: [:], body: Data(json.utf8))
                }
                let json =
                    #"{"skills":[{"id":"owner/fast/fast","skillId":"fast","name":"fast","installs":1,"source":"owner/fast"}]}"#
                return .init(statusCode: 200, headers: [:], body: Data(json.utf8))
            }
        )

        model.searchInput = "slow"
        let slow = Task { await model.runSearchNow() }
        try await Task.sleep(nanoseconds: 50_000_000)
        model.searchInput = "fast"
        await model.runSearchNow()
        await slow.value

        #expect(model.skills.count == 1)
        #expect(model.skills.first?.skillId == "fast")
        #expect(model.totalCount == 1)
    }

    @Test("toggleAgentForInstall flips membership in selectedAgentsForInstall")
    func toggleAgent() async {
        let model = makeModel()
        model.toggleAgentForInstall(.claudeCode)
        #expect(model.selectedAgentsForInstall.contains(.claudeCode))
        model.toggleAgentForInstall(.claudeCode)
        #expect(!model.selectedAgentsForInstall.contains(.claudeCode))
    }
}
