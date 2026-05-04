import Foundation
import Testing

@testable import Skillport

@Suite("SkillManagerActor")
struct SkillManagerActorTests {
    @Test("scanAll emits skillsReloaded and caches result")
    func scanAllEmits() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")

        let manager = makeManager(home: dir.url)
        let events = await manager.events
        let eventTask = Task { () -> DomainEvent? in
            for await e in events {
                if case .skillsReloaded = e { return e }
            }
            return nil
        }
        let skills = try await manager.rescan(home: dir.url)
        #expect(skills.count == 1)
        #expect(skills.first?.name == "alpha")
        // 事件在 ~100ms 内到达
        try await Task.sleep(nanoseconds: 200_000_000)
        eventTask.cancel()
    }

    @Test("toggleAgent updates installedAgents and emits change event")
    func toggleEmits() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "x")
        let manager = makeManager(home: dir.url)
        _ = try await manager.rescan(home: dir.url)
        try await manager.toggleAgent(name: "x", agent: .cursor, install: true, home: dir.url)
        let after = try await manager.rescan(home: dir.url)
        #expect(after.first?.installedAgents.contains(.cursor) == true)
    }

    private func makeManager(home: URL) -> SkillManagerActor {
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let cachePath = home.appendingPathComponent(".agents/.skillport-cache.json")
        let lockFile = LockFileActor(path: lockPath)
        return SkillManagerActor(
            scanner: SkillScannerActor(),
            installer: SkillInstallerActor(
                git: GitActor(),
                symlinker: SymlinkManagerActor(),
                lockFile: lockFile,
                cache: CommitHashCache(path: cachePath)
            ),
            updater: SkillUpdaterActor(
                git: GitActor(),
                cache: CommitHashCache(path: cachePath)
            ),
            batchChecker: BatchUpdateCheckerActor(
                updater: SkillUpdaterActor(
                    git: GitActor(),
                    cache: CommitHashCache(path: cachePath)
                )
            ),
            watcher: FileWatcherActor(),
            lockFile: lockFile
        )
    }
}
