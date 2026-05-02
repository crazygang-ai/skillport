import Foundation
import Testing

@testable import Skillport

@Suite("RegistryActor", .serialized)
struct RegistryActorTests {
    @Test("Fetches and parses skills.sh listing JSON")
    func fetchListing() async throws {
        await MockURLProtocol.reset()
        let listingURL = URL(string: "https://skills.sh/api/skills.json")!
        let body = """
            [
              {"slug": "obra/superpowers", "name": "superpowers", "category": "productivity"},
              {"slug": "anthropic/core", "name": "core", "category": "core"}
            ]
            """
        await MockURLProtocol.stub(url: listingURL) { _ in
            .init(
                statusCode: 200, headers: ["Content-Type": "application/json"],
                body: Data(body.utf8))
        }
        let session = mockSession()
        let registry = RegistryActor(session: session, listingURL: listingURL)
        let entries = try await registry.fetchListing()
        #expect(entries.count == 2)
        #expect(entries[0].slug == "obra/superpowers")
        #expect(entries[0].category == "productivity")
    }

    @Test("Filters entries by query and category")
    func filterEntries() async throws {
        let entries = [
            RegistryEntry(slug: "a/x", name: "x", category: "dev"),
            RegistryEntry(slug: "b/y", name: "y", category: "ops"),
            RegistryEntry(slug: "c/zany", name: "zany", category: "dev"),
        ]
        let filtered = RegistryActor.filter(entries: entries, query: "y", category: "dev")
        #expect(filtered.map(\.name) == ["zany"])
    }

    private func mockSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self] + (cfg.protocolClasses ?? [])
        return URLSession(configuration: cfg)
    }
}
