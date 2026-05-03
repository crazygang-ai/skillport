import Foundation
import Testing

@testable import Skillport

@MainActor
@Suite("M5 Registry E2E", .serialized)
struct RegistryE2ETests {
    @Test("leaderboard → select HTML skill → content rendered via sanitizer path")
    func htmlBranchEnd2End() async throws {
        MockURLProtocol.resetSync()
        let leaderboardHTML = try String(
            contentsOf: #require(
                TestBundleLocator.bundle.url(
                    forResource: "skills-sh-leaderboard-alltime", withExtension: "html")),
            encoding: .utf8)
        MockURLProtocol.stub(
            url: URL(string: "https://skills.sh/")!,
            status: 200,
            body: Data(leaderboardHTML.utf8)
        )
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 404,
            body: Data()
        )
        // Skill content comes back as a T-chunk with HTML (Strategy 2).
        // Chunk must be >= 50 bytes to pass the noise threshold.
        let body =
            "<h1>hello</h1><p>an elaborate description that passes fifty byte threshold</p>"
        let rsc = makeFakeRSCPayload(htmlBody: body)
        MockURLProtocol.stub(
            urlMatch: { $0.host == "skills.sh" && $0.path != "/" },
            status: 200,
            body: Data(rsc.utf8)
        )

        let registry = RegistryActor(session: MockURLProtocol.makeSession())
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        let installer: RegistryModel.InstallHandler = { _, _, _, _ in
            throw SkillportError.unexpected("install not exercised in this test")
        }
        let model = RegistryModel(
            registry: registry,
            contentFetcher: fetcher,
            installHandler: installer
        )

        await model.loadLeaderboard()
        let first = try #require(model.skills.first)
        await model.select(id: first.id)

        switch model.rendered {
        case .attributed(let s):
            let text = String(s.characters)
            #expect(text.contains("hello"))
        // sanitizer would have stripped any script/iframe; here we just verify render succeeded
        default:
            Issue.record("expected .attributed branch, got \(model.rendered)")
        }
    }

    @Test("search → select markdown skill → content rendered via markdown path")
    func markdownBranchEnd2End() async throws {
        MockURLProtocol.resetSync()
        let json = #"{"skills":[{"id":"a/b/b","skillId":"b","name":"b","installs":0,"source":"a/b"}]}"#
        MockURLProtocol.stub(
            urlMatch: { $0.path == "/api/search" },
            status: 200,
            body: Data(json.utf8)
        )
        MockURLProtocol.stub(
            urlMatch: { $0.host == "raw.githubusercontent.com" },
            status: 200,
            body: Data("# Hello from raw\n\nparagraph body".utf8)
        )

        let model = RegistryModel(
            registry: RegistryActor(session: MockURLProtocol.makeSession()),
            contentFetcher: SkillContentFetcher(session: MockURLProtocol.makeSession()),
            installHandler: { _, _, _, _ in
                throw SkillportError.unexpected("install not exercised")
            }
        )
        model.searchInput = "anything"
        await model.runSearchNow()
        #expect(model.skills.count == 1)
        await model.select(id: "a/b/b")
        switch model.rendered {
        case .markdown(let s):
            let text = String(s.characters)
            #expect(text.contains("Hello from raw"))
            #expect(text.contains("paragraph body"))
        default:
            Issue.record("expected .markdown branch, got \(model.rendered)")
        }
    }

    @Test("install button disabled for multi-skill repos (ADR-M5-2)")
    func multiSkillRepoBlocked() async {
        let model = RegistryModel(
            registry: RegistryActor(session: MockURLProtocol.makeSession()),
            contentFetcher: SkillContentFetcher(session: MockURLProtocol.makeSession()),
            installHandler: { _, _, _, _ in
                Issue.record("install should not be called for multi-skill repo")
                throw SkillportError.unexpected("should not reach")
            }
        )
        model.skills = [
            RegistrySkill(
                id: "owner/repo/subsk", skillId: "subsk",
                name: "Sub Skill", installs: 0, source: "owner/repo"
            )
        ]
        model.selectedID = "owner/repo/subsk"
        model.selectedAgentsForInstall = [.claudeCode]
        let result = await model.installSelected()
        switch result {
        case .failure:
            break  // 期望
        case .success:
            Issue.record("multi-skill install should have failed")
        }
    }
}

private func makeFakeRSCPayload(htmlBody: String) -> String {
    let size = String(htmlBody.utf8.count, radix: 16)
    return "a:T\(size),\(htmlBody)\nb:T1,x\n"
}
