import Foundation
import Testing

@testable import Skillport

@Suite("RepoCacheActor")
struct RepoCacheActorTests {
    @Test("first acquire clones; second acquire reuses the same dest")
    func acquireReuses() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let bare = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)
        let root = dir.url.appendingPathComponent("cache")
        let cache = RepoCacheActor(git: GitActor(), root: root)
        let first = try await cache.acquire(url: bare, ref: "HEAD")
        let second = try await cache.acquire(url: bare, ref: "HEAD")
        #expect(first == second)
        #expect(FileManager.default.fileExists(atPath: first.appendingPathComponent(".git").path))
    }

    @Test("concurrent acquire of same (url, ref) shares a single clone Task")
    func inflightDedup() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let bare = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)
        let cache = RepoCacheActor(git: GitActor(), root: dir.url.appendingPathComponent("cache"))
        async let a = cache.acquire(url: bare, ref: "HEAD")
        async let b = cache.acquire(url: bare, ref: "HEAD")
        let (pa, pb) = try await (a, b)
        #expect(pa == pb)
    }

    @Test("cleanupAll removes cache root")
    func cleanup() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let bare = try GitFixtures.makeBareRepoWithRootSKILL(under: dir.url)
        let root = dir.url.appendingPathComponent("cache")
        let cache = RepoCacheActor(git: GitActor(), root: root)
        _ = try await cache.acquire(url: bare, ref: "HEAD")
        #expect(FileManager.default.fileExists(atPath: root.path))
        await cache.cleanupAll()
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
