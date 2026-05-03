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

    @Test("toggleAgentForInstall flips membership in selectedAgentsForInstall")
    func toggleAgent() async {
        let model = makeModel()
        model.toggleAgentForInstall(.claudeCode)
        #expect(model.selectedAgentsForInstall.contains(.claudeCode))
        model.toggleAgentForInstall(.claudeCode)
        #expect(!model.selectedAgentsForInstall.contains(.claudeCode))
    }
}
