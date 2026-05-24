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
        #expect(model.agents.first?.id == .codex)
    }

    @Test("initial refresh publishes available-first agent order")
    func initialRefreshPublishesAvailableFirstAgentOrder() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
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

        try await model.refresh()

        #expect(model.hasDetectedAgents == true)
        #expect(model.skills.count == 1)
        #expect(model.agents.first?.id == .codex)
    }

    @Test("refresh also updates agent availability when config dirs change")
    func refreshUpdatesAgentAvailability() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bin = try dir.mkdir("empty-bin")
        let manager = makeManager(home: home)
        let model = SkillsModel(
            manager: manager,
            home: home,
            detector: AgentDetector(pathOverride: bin.path)
        )

        try await model.refresh()
        #expect(model.agents.first { $0.id == .codex }?.isInstalled == false)

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )

        try await model.refresh()
        #expect(model.agents.first { $0.id == .codex }?.isInstalled == true)
    }

    @Test("skillsReloaded events refresh agent availability after external rescans")
    func skillsReloadedEventRefreshesAgentAvailability() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bin = try dir.mkdir("empty-bin")
        let manager = makeManager(home: home)
        let model = SkillsModel(
            manager: manager,
            home: home,
            detector: AgentDetector(pathOverride: bin.path)
        )

        await model.refreshAgents()
        #expect(model.agents.first { $0.id == .codex }?.isInstalled == false)

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        _ = try await manager.rescan(home: home)
        try await Task.sleep(for: .milliseconds(300))

        #expect(model.agents.first { $0.id == .codex }?.isInstalled == true)
    }

    @Test("isManagedSkill distinguishes canonical and external agent skills")
    func isManagedSkill() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let source = try dir.mkdir("owned")
        try "---\n---\n".write(
            to: source.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "unowned")
        _ = try AgentsFS.createForeignSkill(
            in: dir.url,
            agentRelativeSkillsDir: ".claude/skills",
            name: "external"
        )

        let manager = makeManager(home: dir.url)
        let model = SkillsModel(manager: manager, home: dir.url)
        _ = try await model.installLocal(from: source, installTo: [])
        try await model.refresh()
        let byName = Dictionary(uniqueKeysWithValues: model.skills.map { ($0.name, $0) })

        let owned = try #require(byName["owned"])
        let unowned = try #require(byName["unowned"])
        let external = try #require(byName["external"])
        #expect(model.isManagedSkill(owned) == true)
        #expect(model.isManagedSkill(unowned) == false)
        #expect(model.isManagedSkill(external) == false)
    }

    @Test("skillsFiltered supports search query and ownership filter")
    func skillsFilteredWithSearchAndOwnership() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let source = try dir.mkdir("owned")
        try "---\ndescription: Managed Alpha\n---\n# Body\n".write(
            to: source.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        _ = try AgentsFS.createForeignSkill(
            in: dir.url,
            agentRelativeSkillsDir: ".claude/skills",
            name: "external-beta"
        )

        let manager = makeManager(home: dir.url)
        let model = SkillsModel(manager: manager, home: dir.url)
        _ = try await model.installLocal(from: source, installTo: [])
        try await model.refresh()

        let managed = model.skillsFiltered(
            by: nil,
            query: "alpha",
            ownership: .managed
        )
        #expect(managed.map(\.name) == ["owned"])

        let external = model.skillsFiltered(
            by: nil,
            query: "beta",
            ownership: .external
        )
        #expect(external.map(\.name) == ["external-beta"])
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

    @Test("dismissUpdate marks model up-to-date and records dismissed hash")
    func dismissUpdateWritesLockfileAndModel() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let canonical = try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        let lockPath = dir.url.appendingPathComponent(".agents/.skill-lock.json")
        let lockFile = LockFileActor(path: lockPath)
        let source = SkillSource.github(owner: "owner", repo: "repo", ref: "main")
        try await lockFile.upsert(
            LockedSkill(
                name: "alpha",
                source: source,
                installedAt: Date(),
                commitHash: nil,
                path: canonical
            )
        )
        let checker = BatchUpdateCheckerActor(maxConcurrent: 1) { skill in
            skill.name == "alpha" ? .available(remoteHash: "remote-alpha") : .upToDate
        }
        let manager = makeManager(home: dir.url, batchChecker: checker)
        let model = SkillsModel(manager: manager, home: dir.url)
        try await model.refresh()
        _ = try await model.checkAllUpdates()

        try await model.dismissUpdate(name: "alpha", remoteHash: "remote-alpha")

        let skill = try #require(model.skills.first { $0.name == "alpha" })
        #expect(skill.updateStatus == .upToDate)
        let lock = try await lockFile.read()
        #expect(lock.skills.first { $0.name == "alpha" }?.dismissedUpdate == "remote-alpha")
    }

    @Test("uninstall removes the skill from the model without a separate refresh")
    func uninstallRefreshesModel() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("delete-me")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let manager = makeManager(home: dir.url)
        let model = SkillsModel(manager: manager, home: dir.url)
        _ = try await model.installLocal(from: src, installTo: [])
        try await model.refresh()
        #expect(model.skills.contains { $0.name == "delete-me" })

        try await model.uninstall(name: "delete-me")

        #expect(!model.skills.contains { $0.name == "delete-me" })
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
