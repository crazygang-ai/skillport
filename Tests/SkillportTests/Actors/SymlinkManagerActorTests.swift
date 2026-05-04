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

    @Test("canInherit returns true when a fallback dir already holds a symlink to target")
    func canInheritViaSymlinkFallback() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let canonical = try dir.mkdir("agents/skills/demo")
        let fallbackDir = try dir.mkdir(".agents/skills")
        let fallbackLink = fallbackDir.appendingPathComponent("demo")
        try FileManager.default.createSymbolicLink(
            at: fallbackLink, withDestinationURL: canonical)
        let agentLink = dir.url.appendingPathComponent(".cursor/skills/demo")
        let mgr = SymlinkManagerActor()
        let inherits = await mgr.canInherit(
            target: canonical, linkURL: agentLink, fallbackChain: [fallbackDir])
        #expect(inherits == true)
    }

    @Test("canInherit returns false when no fallback dir has the entry")
    func canInheritFalseWhenNoMatch() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let canonical = try dir.mkdir("agents/skills/demo")
        let fallbackDir = try dir.mkdir(".claude/skills")
        let agentLink = dir.url.appendingPathComponent(".cursor/skills/demo")
        let mgr = SymlinkManagerActor()
        let inherits = await mgr.canInherit(
            target: canonical, linkURL: agentLink, fallbackChain: [fallbackDir])
        #expect(inherits == false)
    }

    @Test("removeInstallation unlinks matching symlink, ignores mismatched symlink")
    func removeInstallationSymlinks() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let canonical = try dir.mkdir("canonical")
        let other = try dir.mkdir("other")
        let fm = FileManager.default
        let link1 = dir.url.appendingPathComponent("l1")
        let link2 = dir.url.appendingPathComponent("l2")
        try fm.createSymbolicLink(at: link1, withDestinationURL: canonical)
        try fm.createSymbolicLink(at: link2, withDestinationURL: other)
        let mgr = SymlinkManagerActor()
        try await mgr.removeInstallation(at: link1, canonical: canonical)
        try await mgr.removeInstallation(at: link2, canonical: canonical)
        #expect(!fm.fileExists(atPath: link1.path))
        // link2 was pointing elsewhere — leave it alone.
        #expect(fm.fileExists(atPath: link2.path))
    }

    @Test("removeInstallation deletes a real directory (copy-type install)")
    func removeInstallationCopyType() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let canonical = try dir.mkdir("canonical")
        let copyInstall = try dir.mkdir("agent/skills/demo")
        try "x".write(
            to: copyInstall.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let mgr = SymlinkManagerActor()
        try await mgr.removeInstallation(at: copyInstall, canonical: canonical)
        #expect(!FileManager.default.fileExists(atPath: copyInstall.path))
    }

    @Test("removeInstallation is no-op when path does not exist")
    func removeInstallationMissing() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let canonical = try dir.mkdir("canonical")
        let missing = dir.url.appendingPathComponent("ghost")
        let mgr = SymlinkManagerActor()
        // Must not throw.
        try await mgr.removeInstallation(at: missing, canonical: canonical)
    }
}
