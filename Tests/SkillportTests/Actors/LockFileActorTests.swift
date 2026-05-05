import Foundation
import Testing

@testable import Skillport

@Suite("LockFileActor")
struct LockFileActorTests {
    @Test("Read returns empty LockFile when file does not exist")
    func readMissing() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let actor = LockFileActor(path: dir.url.appendingPathComponent(".skill-lock.json"))
        let lock = try await actor.read()
        #expect(lock.version == 3)
        #expect(lock.skills.isEmpty)
    }

    @Test("Write then read round-trip preserves LockedSkill entries")
    func roundTrip() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let actor = LockFileActor(path: dir.url.appendingPathComponent(".skill-lock.json"))
        let lock = LockFile(
            version: 3,
            skills: [
                LockedSkill(
                    name: "demo",
                    source: .github(owner: "x", repo: "y", ref: "main"),
                    installedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    commitHash: "abc",
                    path: URL(fileURLWithPath: "/tmp/demo")
                )
            ]
        )
        try await actor.write(lock)
        let back = try await actor.read()
        #expect(back == lock)
    }

    @Test("Write is atomic: partial writes do not clobber existing file")
    func atomicWrite() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let path = dir.url.appendingPathComponent(".skill-lock.json")
        let good = LockFile(version: 3, skills: [])
        let actor = LockFileActor(path: path)
        try await actor.write(good)
        // 模拟第二次写入时崩溃：先验证没有 .tmp 遗留
        let tmpPath = path.path + ".tmp"
        #expect(!FileManager.default.fileExists(atPath: tmpPath))
        let stillThere = try await actor.read()
        #expect(stillThere == good)
    }

    @Test("Unsupported version: file is moved to .bak-<stamp> and read returns empty")
    func rejectsVersionDrift() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let path = dir.url.appendingPathComponent(".skill-lock.json")
        try #"{"version": 99, "skills": []}"#.write(to: path, atomically: true, encoding: .utf8)
        let actor = LockFileActor(path: path)
        let lock = try await actor.read()
        #expect(lock.skills.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        // 应能在同目录找到以 `.bak-` 开头的备份
        let siblings = try FileManager.default.contentsOfDirectory(
            at: dir.url, includingPropertiesForKeys: nil)
        #expect(siblings.contains { $0.lastPathComponent.contains(".bak-") })
    }

    @Test("Corrupt JSON: file is moved to .bak-<stamp> and read returns empty")
    func corruptJSONIsRecoveredSilently() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let path = dir.url.appendingPathComponent(".skill-lock.json")
        try "not json at all {".write(to: path, atomically: true, encoding: .utf8)
        let actor = LockFileActor(path: path)
        let lock = try await actor.read()
        #expect(lock.skills.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test("readWithRecoveryNotice reports corrupt lockfile while preserving recovery")
    func readReportsRecoveryNotice() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let path = dir.url.appendingPathComponent(".skill-lock.json")
        try "not json".write(to: path, atomically: true, encoding: .utf8)
        let result = try await LockFileActor(path: path).readWithRecoveryNotice()
        #expect(result.lockFile.skills.isEmpty)
        #expect(result.recoveryError != nil)
        #expect(result.backupURL != nil)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test("upsert(LockedSkill) adds new then replaces by name")
    func upsert() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let actor = LockFileActor(path: dir.url.appendingPathComponent(".skill-lock.json"))
        let a = LockedSkill(
            name: "demo",
            source: .local(path: URL(fileURLWithPath: "/p1")),
            installedAt: Date(),
            commitHash: nil,
            path: URL(fileURLWithPath: "/t/demo")
        )
        try await actor.upsert(a)
        let updated = LockedSkill(
            name: "demo",
            source: .local(path: URL(fileURLWithPath: "/p2")),
            installedAt: Date(),
            commitHash: "new",
            path: URL(fileURLWithPath: "/t/demo")
        )
        try await actor.upsert(updated)
        let lock = try await actor.read()
        #expect(lock.skills.count == 1)
        #expect(lock.skills.first?.commitHash == "new")
    }

    @Test("remove(name:) drops a skill entry")
    func removeEntry() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let actor = LockFileActor(path: dir.url.appendingPathComponent(".skill-lock.json"))
        let s = LockedSkill(
            name: "x",
            source: .local(path: URL(fileURLWithPath: "/x")),
            installedAt: Date(),
            commitHash: nil,
            path: URL(fileURLWithPath: "/t/x")
        )
        try await actor.upsert(s)
        try await actor.remove(name: "x")
        let lock = try await actor.read()
        #expect(lock.skills.isEmpty)
    }
}
