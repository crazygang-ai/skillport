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
        let installer: RegistryModel.InstallHandler = { _, _, _, _, _ in
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
            installHandler: { _, _, _, _, _ in
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

    @Test("install passes skillId through to handler for multi-skill repos")
    func multiSkillPassesSkillIdThrough() async {
        let receivedBox = ReceivedBox()
        let model = RegistryModel(
            registry: RegistryActor(session: MockURLProtocol.makeSession()),
            contentFetcher: SkillContentFetcher(session: MockURLProtocol.makeSession()),
            installHandler: { owner, repo, ref, skillId, installTo in
                await receivedBox.set(skillId: skillId)
                return Skill(
                    name: skillId,
                    path: URL(fileURLWithPath: "/tmp/\(skillId)"),
                    source: .github(owner: owner, repo: repo, ref: ref),
                    frontmatter: SKILLMetadata(),
                    installedAgents: installTo,
                    updateStatus: .upToDate
                )
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
        if case .failure(let err) = result {
            Issue.record("install should succeed; got \(err)")
        }
        let captured = await receivedBox.skillId
        #expect(captured == "subsk")
    }

    @Test("multi-skill E2E: search → select subskill → install extracts subdir only")
    func multiSkillInstallEndToEnd() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["pilot", "scout"])

        MockURLProtocol.resetSync()
        let json =
            #"{"skills":[{"id":"test/example/pilot","skillId":"pilot","name":"pilot","installs":0,"source":"test/example"}]}"#
        MockURLProtocol.stub(
            urlMatch: { $0.path == "/api/search" },
            status: 200, body: Data(json.utf8)
        )

        let registry = RegistryActor(session: MockURLProtocol.makeSession())
        let fetcher = SkillContentFetcher(session: MockURLProtocol.makeSession())
        let git = GitActor()
        let symlinker = SymlinkManagerActor()
        let lockFile = LockFileActor(
            path: home.appendingPathComponent(".agents/.skill-lock.json"))
        let cache = CommitHashCache(
            path: home.appendingPathComponent(".agents/.cache.json"))
        let installer = SkillInstallerActor(
            git: git, symlinker: symlinker, lockFile: lockFile, cache: cache)

        let model = RegistryModel(
            registry: registry, contentFetcher: fetcher,
            installHandler: { _, _, ref, skillId, installTo in
                try await installer.installGitHub(
                    sourceURL: bareRepo,
                    owner: "test", repo: "example", ref: ref,
                    skillId: skillId, home: home, installTo: installTo)
            }
        )

        model.searchInput = "pilot"
        await model.runSearchNow()
        #expect(model.skills.count == 1)
        await model.select(id: "test/example/pilot")
        model.selectedAgentsForInstall = []  // 不 install 到 agent, 只验 canonical
        let result = await model.installSelected()
        if case .failure(let err) = result {
            Issue.record("install failed: \(err)")
        }
        // canonical dir 是 pilot 不是 example
        let pilotDir = home.appendingPathComponent(".agents/skills/pilot")
        #expect(
            FileManager.default.fileExists(
                atPath: pilotDir.appendingPathComponent("SKILL.md").path))
        // scout 没被拉过来
        let scoutDir = home.appendingPathComponent(".agents/skills/scout")
        #expect(!FileManager.default.fileExists(atPath: scoutDir.path))
    }
}

/// Test helper — thread-safe box to capture skillId from @Sendable install handler.
private actor ReceivedBox {
    var skillId: String?
    func set(skillId: String) { self.skillId = skillId }
}

private func makeFakeRSCPayload(htmlBody: String) -> String {
    let size = String(htmlBody.utf8.count, radix: 16)
    return "a:T\(size),\(htmlBody)\nb:T1,x\n"
}
