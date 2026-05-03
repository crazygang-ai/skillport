import Foundation
import Testing

@testable import Skillport

@Suite("RegistryActor — leaderboard + search via skills.sh", .serialized)
struct RegistryActorTests {
    @Test("leaderboard(.allTime) fetches / and parses RSC payload")
    func leaderboardAllTime() async throws {
        MockURLProtocol.resetSync()
        let html = try loadFixture("skills-sh-leaderboard-alltime")
        MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/")!,
            status: 200,
            body: Data(html.utf8)
        )
        let actor = RegistryActor(session: MockURLProtocol.makeSession())
        let result = try await actor.leaderboard(.allTime)
        #expect(result.skills.count > 0)
        #expect(result.totalCount >= result.skills.count)
    }

    @Test("leaderboard(.trending) hits /trending path")
    func leaderboardTrending() async throws {
        MockURLProtocol.resetSync()
        let html = try loadFixture("skills-sh-leaderboard-alltime")
        MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/trending")!,
            status: 200,
            body: Data(html.utf8)
        )
        let actor = RegistryActor(session: MockURLProtocol.makeSession())
        _ = try await actor.leaderboard(.trending)
        let called = MockURLProtocol.requestLog.map { $0.url?.path ?? "" }
        #expect(called.contains("/trending"))
    }

    @Test("leaderboard uses in-memory cache within TTL")
    func leaderboardCache() async throws {
        MockURLProtocol.resetSync()
        let html = try loadFixture("skills-sh-leaderboard-alltime")
        MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/")!,
            status: 200,
            body: Data(html.utf8)
        )
        let actor = RegistryActor(session: MockURLProtocol.makeSession())
        _ = try await actor.leaderboard(.allTime)
        _ = try await actor.leaderboard(.allTime)
        let calls = MockURLProtocol.requestLog.filter { $0.url?.host == "skills.sh" }
        #expect(calls.count == 1)
    }

    @Test("leaderboard 500 throws networkFailed")
    func leaderboard500() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/")!,
            status: 500,
            body: Data()
        )
        let actor = RegistryActor(session: MockURLProtocol.makeSession())
        await #expect(throws: SkillportError.self) {
            _ = try await actor.leaderboard(.allTime)
        }
    }

    @Test("search encodes query and parses JSON response")
    func search() async throws {
        MockURLProtocol.resetSync()
        let json = """
            {"skills":[
              {"id":"a/b/c","skillId":"c","name":"cool","installs":42,"source":"a/b"},
              {"id":"d/e/f","skillId":"f","name":"fast","installs":99,"source":"d/e","installs_yesterday":5,"change":2}
            ]}
            """
        MockURLProtocol.stub(
            urlMatch: { $0.path == "/api/search" && ($0.query?.contains("q=helm") ?? false) },
            status: 200,
            body: Data(json.utf8)
        )
        let actor = RegistryActor(session: MockURLProtocol.makeSession())
        let skills = try await actor.search(query: "helm")
        #expect(skills.count == 2)
        #expect(skills[0].skillId == "c")
        #expect(skills[1].installsYesterday == 5)
        #expect(skills[1].change == 2)
    }

    @Test("search clamps limit to upper bound of 100")
    func searchLimitClamp() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: { _ in true },
            status: 200,
            body: Data(#"{"skills":[]}"#.utf8)
        )
        let actor = RegistryActor(session: MockURLProtocol.makeSession())
        _ = try await actor.search(query: "x", limit: 999)
        let q = MockURLProtocol.requestLog.last?.url?.query ?? ""
        #expect(q.contains("limit=100"))
    }

    // MARK: - Helper

    private func loadFixture(_ name: String) throws -> String {
        let url = try #require(
            TestBundleLocator.bundle.url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
