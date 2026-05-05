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

    @Test("rescan emits invalidLockFile error when corrupt lockfile is recovered")
    func corruptLockfileEmitsError() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        let lockPath = dir.url.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(
            at: lockPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "bad json".write(to: lockPath, atomically: true, encoding: .utf8)

        let manager = makeManager(home: dir.url)
        let events = await manager.events
        let eventTask = Task { () -> SkillportError? in
            for await event in events {
                if case .error(let error) = event {
                    return error
                }
            }
            return nil
        }

        _ = try await manager.rescan(home: dir.url)
        let error = await eventTask.value
        #expect(error != nil)
        if case .invalidLockFile = error {
            // expected
        } else {
            Issue.record("expected invalidLockFile, got \(String(describing: error))")
        }
        let siblings = try FileManager.default.contentsOfDirectory(
            at: lockPath.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(siblings.contains { $0.lastPathComponent.contains(".bak-") })
    }

    @Test("rescan preserves update statuses computed by update checks")
    func rescanPreservesUpdateStatus() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        try AgentsFS.createCanonicalSkill(in: dir.url, name: "alpha")
        let manager = makeManager(home: dir.url) { skill in
            skill.name == "alpha" ? .available(remoteHash: "remote-alpha") : .upToDate
        }

        let initial = try await manager.rescan(home: dir.url)
        _ = try await manager.checkAllUpdates(skills: initial)
        let after = try await manager.rescan(home: dir.url)

        #expect(after.first?.updateStatus == .available(remoteHash: "remote-alpha"))
    }

    private func makeManager(
        home: URL,
        checkStatus: (@Sendable (Skill) async throws -> UpdateStatus)? = nil
    ) -> SkillManagerActor {
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let cachePath = home.appendingPathComponent(".agents/.skillport-cache.json")
        let lockFile = LockFileActor(path: lockPath)
        let updater = SkillUpdaterActor(
            git: GitActor(),
            cache: CommitHashCache(path: cachePath)
        )
        return SkillManagerActor(
            scanner: SkillScannerActor(),
            installer: SkillInstallerActor(
                git: GitActor(),
                symlinker: SymlinkManagerActor(),
                lockFile: lockFile,
                cache: CommitHashCache(path: cachePath)
            ),
            updater: updater,
            batchChecker: checkStatus.map { BatchUpdateCheckerActor(checkStatus: $0) }
                ?? BatchUpdateCheckerActor(updater: updater),
            watcher: FileWatcherActor(),
            lockFile: lockFile
        )
    }
}
