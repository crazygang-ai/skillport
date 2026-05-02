import Foundation
import Testing

@testable import Skillport

@Suite("SymlinkManagerActor")
struct SymlinkManagerActorTests {
    @Test("Creates symlink pointing at target")
    func createLink() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let target = try dir.mkdir("target")
        let linkDir = try dir.mkdir("agent-skills")
        let link = linkDir.appendingPathComponent("demo")
        let mgr = SymlinkManagerActor()
        try await mgr.link(target: target, at: link)
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(resolved == target.path)
    }

    @Test("link is idempotent: same target → no-op")
    func idempotent() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let target = try dir.mkdir("t")
        let link = dir.url.appendingPathComponent("l")
        let mgr = SymlinkManagerActor()
        try await mgr.link(target: target, at: link)
        try await mgr.link(target: target, at: link)  // 不 throw
        let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(resolved == target.path)
    }

    @Test("link replaces a link pointing elsewhere")
    func replaceExisting() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let t1 = try dir.mkdir("t1")
        let t2 = try dir.mkdir("t2")
        let link = dir.url.appendingPathComponent("l")
        let mgr = SymlinkManagerActor()
        try await mgr.link(target: t1, at: link)
        try await mgr.link(target: t2, at: link)
        let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(resolved == t2.path)
    }

    @Test("unlink removes only if it is a symlink pointing at expected target")
    func unlinkSafe() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let target = try dir.mkdir("t")
        let link = dir.url.appendingPathComponent("l")
        let mgr = SymlinkManagerActor()
        try await mgr.link(target: target, at: link)
        try await mgr.unlink(at: link, expectedTarget: target)
        #expect(!FileManager.default.fileExists(atPath: link.path))
    }

    @Test("unlink refuses to remove a real directory at the link path")
    func unlinkRefusesRealDir() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let fakeTarget = try dir.mkdir("real")
        await #expect(throws: SkillportError.self) {
            try await SymlinkManagerActor().unlink(at: fakeTarget, expectedTarget: fakeTarget)
        }
    }
}
