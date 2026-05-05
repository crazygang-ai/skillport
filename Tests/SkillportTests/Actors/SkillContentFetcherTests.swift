import Foundation
import Testing

@testable import Skillport

@Suite("SkillContentFetcher", .serialized)
struct SkillContentFetcherTests {
    @Test("Returns first 200 response among parallel candidates")
    func racesCandidates() async throws {
        await MockURLProtocol.reset()
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

@Suite("SkillContentFetcher — 3-tier cascade", .serialized)
struct SkillContentFetcherCascadeTests {
    @Test("strategy 1 wins when any raw URL candidate returns 200")
    func strategy1Wins() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: {
                $0.host == "raw.githubusercontent.com" && $0.path.hasSuffix("/main/SKILL.md")
            },
            status: 200,
            body: Data("# hello from raw".utf8)
        )
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        let content = try await fetcher.fetchContent(source: "owner/repo", skillId: "repo")
        #expect(content.contains("# hello from raw"))
        let touched = MockURLProtocol.requestLog.map { $0.url?.host ?? "" }
        #expect(!touched.contains("skills.sh"))
        #expect(!touched.contains("api.github.com"))
    }

    @Test("strategy 2 fires when all raw URLs fail; returns HTML prefixed content")
    func strategy2SkillsShFallback() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 404,
            body: Data()
        )
        let rsc = makeFakeRSCPayload(
            htmlBody: "<h1>docs</h1><p>long enough to pass the fifty byte threshold</p>")
        MockURLProtocol.stub(
            urlMatch: { $0.host == "skills.sh" },
            status: 200,
            body: Data(rsc.utf8)
        )
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        let content = try await fetcher.fetchContent(source: "owner/repo", skillId: "sub")
        #expect(content.hasPrefix("<!-- HTML -->"))
        #expect(content.contains("<h1>docs</h1>"))
    }

    @Test("strategy 3 hits Tree API + raw file when strategies 1 and 2 both fail")
    func strategy3TreeAPI() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: {
                $0.host == "raw.githubusercontent.com" && !$0.path.contains("skills/sub/SKILL.md")
            },
            status: 404,
            body: Data()
        )
        MockURLProtocol.stub(urlMatch: { $0.host == "skills.sh" }, status: 404, body: Data())
        let tree = #"{"tree":[{"path":"skills/sub/SKILL.md","type":"blob"}]}"#
        MockURLProtocol.stub(
            urlMatch: { $0.host == "api.github.com" && $0.path.hasSuffix("git/trees/main") },
            status: 200,
            body: Data(tree.utf8)
        )
        MockURLProtocol.stub(
            urlMatch: {
                $0.host == "raw.githubusercontent.com" && $0.path.hasSuffix("skills/sub/SKILL.md")
            },
            status: 200,
            body: Data("# from tree".utf8)
        )
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        let content = try await fetcher.fetchContent(source: "owner/repo", skillId: "sub")
        #expect(content.contains("# from tree"))
    }

    @Test("strategy 3 matches SKILL.md by exact parent directory")
    func strategy3TreeAPIAvoidsSubstringMatch() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: {
                $0.host == "raw.githubusercontent.com"
                    && $0.path.hasSuffix("packages/django/SKILL.md")
            },
            status: 200,
            body: Data("# wrong django doc".utf8)
        )
        MockURLProtocol.stub(
            urlMatch: {
                $0.host == "raw.githubusercontent.com"
                    && $0.path.hasSuffix("packages/go/SKILL.md")
            },
            status: 200,
            body: Data("# correct go doc".utf8)
        )
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 404,
            body: Data()
        )
        MockURLProtocol.stub(urlMatch: { $0.host == "skills.sh" }, status: 404, body: Data())
        let tree =
            #"{"tree":[{"path":"packages/django/SKILL.md","type":"blob"},{"path":"packages/go/SKILL.md","type":"blob"}]}"#
        MockURLProtocol.stub(
            urlMatch: { $0.host == "api.github.com" && $0.path.hasSuffix("git/trees/main") },
            status: 200,
            body: Data(tree.utf8)
        )

        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        let content = try await fetcher.fetchContent(source: "owner/repo", skillId: "go")

        #expect(content.contains("# correct go doc"))
        #expect(!content.contains("django"))
    }

    @Test("content is cached for subsequent calls within TTL")
    func cacheHit() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 200,
            body: Data("# cached".utf8)
        )
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        _ = try await fetcher.fetchContent(source: "owner/repo", skillId: "repo")
        let firstCount = MockURLProtocol.requestLog.count
        MockURLProtocol.clearRequestLog()
        _ = try await fetcher.fetchContent(source: "owner/repo", skillId: "repo")
        let secondCount = MockURLProtocol.requestLog.count
        #expect(firstCount >= 1)
        #expect(secondCount == 0)
    }

    @Test("fetchContent throws when every strategy fails")
    func allStrategiesFailThrows() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 404,
            body: Data()
        )
        MockURLProtocol.stub(urlMatch: { $0.host == "skills.sh" }, status: 404, body: Data())
        MockURLProtocol.stub(urlMatch: { $0.host == "api.github.com" }, status: 404, body: Data())

        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        await #expect(throws: SkillportError.self) {
            _ = try await fetcher.fetchContent(source: "owner/repo", skillId: "missing")
        }
    }

    @Test("GitHub API rate-limit response sets internal reset timer")
    func rateLimitBackoff() async throws {
        MockURLProtocol.resetSync()
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" }, status: 404, body: Data())
        MockURLProtocol.stub(urlMatch: { $0.host == "skills.sh" }, status: 404, body: Data())
        let futureReset = String(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))
        MockURLProtocol.stub(
            urlMatch: { $0.host == "api.github.com" },
            status: 403,
            headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": futureReset],
            body: Data()
        )
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        _ = try? await fetcher.fetchContent(source: "a/b", skillId: "x")
        MockURLProtocol.clearRequestLog()
        _ = try? await fetcher.fetchContent(source: "c/d", skillId: "y")
        let githubApiCalls = MockURLProtocol.requestLog.filter { $0.url?.host == "api.github.com" }
        #expect(githubApiCalls.count == 0)
    }
}

/// Fake RSC payload with a `a:T{sizeHex},{body}` chunk for Strategy 2 tests.
private func makeFakeRSCPayload(htmlBody: String) -> String {
    let size = String(htmlBody.utf8.count, radix: 16)
    return "a:T\(size),\(htmlBody)\nb:T1,x\n"
}
