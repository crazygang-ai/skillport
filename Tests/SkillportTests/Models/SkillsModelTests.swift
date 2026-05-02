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
        try await model.toggle(skillName: "x", agent: .cursor, install: true)
        let found = model.skills.first { $0.name == "x" }!
        #expect(found.installedAgents.contains(.cursor))
        try await model.toggle(skillName: "x", agent: .cursor, install: false)
        let after = model.skills.first { $0.name == "x" }!
        #expect(!after.installedAgents.contains(.cursor))
    }

    private func makeManager(home: URL) -> SkillManagerActor {
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let cachePath = home.appendingPathComponent(".agents/.skillpilot-cache.json")
        let lockFile = LockFileActor(path: lockPath)
        return SkillManagerActor(
            scanner: SkillScannerActor(),
            installer: SkillInstallerActor(
                git: GitActor(),
                symlinker: SymlinkManagerActor(),
                lockFile: lockFile,
                cache: CommitHashCache(path: cachePath)
            ),
            updater: SkillUpdaterActor(git: GitActor(), cache: CommitHashCache(path: cachePath)),
            batchChecker: BatchUpdateCheckerActor(
                updater: SkillUpdaterActor(git: GitActor(), cache: CommitHashCache(path: cachePath))
            ),
            watcher: FileWatcherActor(),
            lockFile: lockFile
        )
    }
}
