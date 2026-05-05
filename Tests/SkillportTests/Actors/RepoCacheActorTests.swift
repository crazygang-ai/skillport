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

    @Test("cached acquire supports tag refs")
    func acquireReusesTagRef() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let bare = try makeTaggedBareRepo(under: dir.url, tag: "v1.0.0")
        let cache = RepoCacheActor(git: GitActor(), root: dir.url.appendingPathComponent("cache"))

        let first = try await cache.acquire(url: bare, ref: "v1.0.0")
        let second = try await cache.acquire(url: bare, ref: "v1.0.0")

        #expect(first == second)
        #expect(FileManager.default.fileExists(atPath: second.appendingPathComponent("SKILL.md").path))
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

    private func makeTaggedBareRepo(under home: URL, tag: String) throws -> URL {
        let workDir = home.appendingPathComponent("tagged-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try "---\ndescription: tag\n---\n# Tagged\n".write(
            to: workDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["init", "-b", "main"], cwd: workDir)
        try runGit(["add", "."], cwd: workDir)
        try runGit(
            ["-c", "user.name=t", "-c", "user.email=t@t.t", "commit", "-m", "init"],
            cwd: workDir
        )
        try runGit(["tag", tag], cwd: workDir)
        let bareURL = home.appendingPathComponent("bare-tag-\(UUID().uuidString).git")
        try runGit(["clone", "--bare", ".", bareURL.path], cwd: workDir)
        return bareURL
    }

    private func runGit(_ args: [String], cwd: URL) throws {
        let process = Process()
        process.currentDirectoryURL = cwd
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message =
                String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? ""
            throw SkillportError.gitFailed(exitCode: process.terminationStatus, stderr: message)
        }
    }
}
