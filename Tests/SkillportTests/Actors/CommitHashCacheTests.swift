import Foundation
import Testing

@testable import Skillport

@Suite("CommitHashCache")
struct CommitHashCacheTests {
    @Test("get returns nil when key missing")
    func missingKey() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let cache = CommitHashCache(path: dir.url.appendingPathComponent(".cache.json"))
        #expect(await cache.get(identity: SkillIdentity(rawValue: "x")) == nil)
    }

    @Test("set then get round-trip persists to disk")
    func setAndGet() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let path = dir.url.appendingPathComponent(".cache.json")
        let cache = CommitHashCache(path: path)
        let id = SkillIdentity(rawValue: "github:a/b@main#c")
        try await cache.set(identity: id, hash: "deadbeef")
        #expect(await cache.get(identity: id) == "deadbeef")

        // 重建一个实例，确认落盘
        let reloaded = CommitHashCache(path: path)
        #expect(await reloaded.get(identity: id) == "deadbeef")
    }

    @Test("remove drops the entry")
    func removeEntry() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let cache = CommitHashCache(path: dir.url.appendingPathComponent(".cache.json"))
        let id = SkillIdentity(rawValue: "x")
        try await cache.set(identity: id, hash: "h")
        try await cache.remove(identity: id)
        #expect(await cache.get(identity: id) == nil)
    }

    @Test("Corrupt cache file is treated as empty (defensive)")
    func corruptFile() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let path = dir.url.appendingPathComponent(".cache.json")
        try "not json".write(to: path, atomically: true, encoding: .utf8)
        let cache = CommitHashCache(path: path)
        #expect(await cache.get(identity: SkillIdentity(rawValue: "x")) == nil)
    }
}
