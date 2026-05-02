import Foundation
import Testing

@testable import Skillport

@Suite("SkillContentFetcher", .serialized)
struct SkillContentFetcherTests {
    @Test("Returns first 200 response among parallel candidates")
    func racesCandidates() async throws {
        await MockURLProtocol.reset()
        // 三条候选，只有一条返回 200
        let fast = URL(string: "https://raw.test/a/SKILL.md")!
        let slow = URL(string: "https://raw.test/b/SKILL.md")!
        let bad = URL(string: "https://raw.test/c/SKILL.md")!
        await MockURLProtocol.stub(url: fast) { _ in
            .init(statusCode: 200, headers: [:], body: Data("# hello".utf8))
        }
        await MockURLProtocol.stub(url: slow) { _ in
            .init(statusCode: 404, headers: [:], body: Data())
        }
        await MockURLProtocol.stub(url: bad) { _ in
            .init(statusCode: 500, headers: [:], body: Data())
        }
        let session = mockSession()
        let fetcher = SkillContentFetcher(session: session)
        let content = try await fetcher.fetchFirstSuccess(from: [fast, slow, bad])
        #expect(String(data: content, encoding: .utf8) == "# hello")
    }

    @Test("Throws when all candidates fail")
    func allFail() async throws {
        await MockURLProtocol.reset()
        let a = URL(string: "https://raw.test/x")!
        let b = URL(string: "https://raw.test/y")!
        await MockURLProtocol.stub(url: a) { _ in
            .init(statusCode: 404, headers: [:], body: Data())
        }
        await MockURLProtocol.stub(url: b) { _ in
            .init(statusCode: 500, headers: [:], body: Data())
        }
        let fetcher = SkillContentFetcher(session: mockSession())
        await #expect(throws: SkillportError.self) {
            _ = try await fetcher.fetchFirstSuccess(from: [a, b])
        }
    }

    private func mockSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self] + (cfg.protocolClasses ?? [])
        return URLSession(configuration: cfg)
    }
}
