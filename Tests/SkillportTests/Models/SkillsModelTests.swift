import Foundation
import Testing

@testable import Skillport

@Suite("SkillsModel")
@MainActor
struct SkillsModelTests {
    @Test("initialRescan populates skills from canonical store")
    func initialRescan() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "beta")

        let manager = makeManager(home: dir.url)
        let model = SkillsModel(manager: manager, home: dir.url)
        try await model.refresh()
        #expect(model.skills.count == 2)
        #expect(model.agents.count == AgentID.allCases.count)
    }

    @Test("toggle(skill:agent:) flips installedAgents")
    func toggleAgent() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "x")
        let manager = makeManager(home: dir.url)
        let model = SkillsModel(manager: manager, home: dir.url)
        try await model.refresh()
        // 用 .kiro —— 它没有 fallbackChain，适合测"直接 symlink"语义。
        // 像 .cursor 这种 fallback 到 .agents/skills 的 agent，即便 symlink 删了也会因
        // 继承 (P0.1) 仍出现在 installedAgents 里，那属于期望行为，不适合这个断言。
        try await model.toggle(skillName: "x", agent: .kiro, install: true)
        let found = model.skills.first { $0.name == "x" }!
        #expect(found.installedAgents.contains(.kiro))
        try await model.toggle(skillName: "x", agent: .kiro, install: false)
        let after = model.skills.first { $0.name == "x" }!
        #expect(!after.installedAgents.contains(.kiro))
    }

    @Test("refreshAgents populates Agent.isInstalled via injected AgentDetector")
    func refreshAgentsPopulatesIsInstalled() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        // Fake bin dir containing only an executable named "codex".
        let bin = try dir.mkdir("bin")
        let fake = bin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let manager = makeManager(home: dir.url)
        let model = SkillsModel(
            manager: manager,
            home: dir.url,
            detector: AgentDetector(pathOverride: bin.path)
        )
        #expect(model.hasDetectedAgents == false)
        #expect(model.isDetectingAgents == false)

        await model.refreshAgents()

        #expect(model.hasDetectedAgents == true)
        #expect(model.isDetectingAgents == false)
        let byID = Dictionary(uniqueKeysWithValues: model.agents.map { ($0.id, $0) })
        #expect(byID[.codex]?.isInstalled == true)
        #expect(byID[.claudeCode]?.isInstalled == false)
        #expect(byID[.kiro]?.isInstalled == false)
    }

    @Test("checkAllUpdates writes update statuses back into model skills")
    func checkAllUpdatesWritesStatuses() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "beta")
        let checker = BatchUpdateCheckerActor(maxConcurrent: 2) { skill in
            skill.name == "alpha" ? .available(remoteHash: "remote-alpha") : .upToDate
        }
        let manager = makeManager(home: dir.url, batchChecker: checker)
        let model = SkillsModel(manager: manager, home: dir.url)
        try await model.refresh()

        _ = try await model.checkAllUpdates()

        let byName = Dictionary(uniqueKeysWithValues: model.skills.map { ($0.name, $0.updateStatus) })
        #expect(byName["alpha"] == .available(remoteHash: "remote-alpha"))
        #expect(byName["beta"] == .upToDate)
    }

    private func makeManager(
        home: URL,
        batchChecker: BatchUpdateCheckerActor? = nil
    ) -> SkillManagerActor {
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let cachePath = home.appendingPathComponent(".agents/.skillport-cache.json")
        let lockFile = LockFileActor(path: lockPath)
        let updater = SkillUpdaterActor(git: GitActor(), cache: CommitHashCache(path: cachePath))
        return SkillManagerActor(
            scanner: SkillScannerActor(),
            installer: SkillInstallerActor(
                git: GitActor(),
                symlinker: SymlinkManagerActor(),
                lockFile: lockFile,
                cache: CommitHashCache(path: cachePath)
            ),
            updater: updater,
            batchChecker: batchChecker ?? BatchUpdateCheckerActor(updater: updater),
            watcher: FileWatcherActor(),
            lockFile: lockFile
        )
    }
}
