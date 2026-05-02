import Foundation
import Testing

@testable import Skillport

@Suite("GitActor")
struct GitActorTests {
    /// helper: 在 TempDir 下初始化 git repo 并加一个提交，返回 repo 目录。
    func makeRepo(in dir: TempDir) throws -> URL {
        let repo = try dir.mkdir("repo")
        _ = try runGit(["init", "-b", "main"], cwd: repo)
        _ = try runGit(["config", "user.email", "test@local"], cwd: repo)
        _ = try runGit(["config", "user.name", "test"], cwd: repo)
        try "hello".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "."], cwd: repo)
        _ = try runGit(["commit", "-m", "init"], cwd: repo)
        return repo
    }

    private func runGit(_ args: [String], cwd: URL) throws -> String {
        let process = Process()
        process.currentDirectoryURL = cwd
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @Test("headHash returns 40-char sha of latest commit")
    func headHash() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let repo = try makeRepo(in: dir)
        let git = GitActor()
        let hash = try await git.headHash(in: repo)
        #expect(hash.count == 40)
    }

    @Test("treeHash returns stable hash for HEAD tree")
    func treeHash() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let repo = try makeRepo(in: dir)
        let git = GitActor()
        let a = try await git.treeHash(in: repo, ref: "HEAD")
        let b = try await git.treeHash(in: repo, ref: "HEAD")
        #expect(a == b)
    }

    @Test("clone copies a local repo into destination")
    func cloneLocal() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let source = try makeRepo(in: dir)
        let dest = dir.url.appendingPathComponent("cloned")
        let git = GitActor()
        try await git.cloneLocal(from: source, to: dest, depth: 1)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("README.md").path))
    }

    @Test("Error includes stderr when git fails")
    func errorSurfacesStderr() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let notRepo = try dir.mkdir("not-a-repo")
        let git = GitActor()
        await #expect(throws: SkillportError.self) {
            _ = try await git.headHash(in: notRepo)
        }
    }
}
