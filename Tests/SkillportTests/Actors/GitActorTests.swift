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

    @Test("clone with ref=HEAD does not pass -b HEAD to git")
    func cloneHeadRefFallsBackToDefault() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let source = try makeRepo(in: dir)
        let dest = dir.url.appendingPathComponent("cloned-head")
        let git = GitActor()
        // 正常 `git clone --branch HEAD` 会报 "Remote branch HEAD not found"。
        // 修复后 ref=="HEAD" 时不拼 -b，clone 默认分支应当成功。
        try await git.clone(url: source, to: dest, ref: "HEAD", depth: 1)
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appendingPathComponent("README.md").path))
    }

    @Test("command timeout terminates long-running git process")
    func commandTimeoutTerminatesProcess() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let fakeGit = try makeSleepingGit(in: dir)
        let git = GitActor(
            executableURL: fakeGit,
            commandPrefix: [],
            commandTimeout: .milliseconds(100)
        )

        let start = Date()
        await #expect(throws: SkillportError.self) {
            _ = try await git.headHash(in: dir.url)
        }
        #expect(Date().timeIntervalSince(start) < 0.8)
    }

    @Test("task cancellation terminates long-running git process")
    func cancellationTerminatesProcess() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let fakeGit = try makeSleepingGit(in: dir)
        let git = GitActor(
            executableURL: fakeGit,
            commandPrefix: [],
            commandTimeout: .seconds(10)
        )

        let task = Task {
            try await git.headHash(in: dir.url)
        }
        try await Task.sleep(for: .milliseconds(100))
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation to fail the git command")
        } catch {
            // Expected: either cancellation or the terminated process error.
        }
        #expect(Date().timeIntervalSince(start) < 0.8)
    }

    @Test("subdirTreeHash returns subdir hash that changes when subdir content changes")
    func subdirTreeHashTracksSubdir() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let repo = try dir.mkdir("repo")
        _ = try runGit(["init", "-b", "main"], cwd: repo)
        _ = try runGit(["config", "user.email", "t@t"], cwd: repo)
        _ = try runGit(["config", "user.name", "t"], cwd: repo)
        let subA = repo.appendingPathComponent("skills/alpha")
        let subB = repo.appendingPathComponent("skills/beta")
        try FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subB, withIntermediateDirectories: true)
        try "a1".write(to: subA.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "b1".write(to: subB.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "."], cwd: repo)
        _ = try runGit(["commit", "-m", "init"], cwd: repo)

        let git = GitActor()
        let hashA1 = try await git.subdirTreeHash(in: repo, subdir: "skills/alpha")
        let hashB1 = try await git.subdirTreeHash(in: repo, subdir: "skills/beta")
        #expect(hashA1 != hashB1)

        // Change only alpha; beta's tree hash must remain stable.
        try "a2".write(to: subA.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "."], cwd: repo)
        _ = try runGit(["commit", "-m", "update alpha"], cwd: repo)
        let hashA2 = try await git.subdirTreeHash(in: repo, subdir: "skills/alpha")
        let hashB2 = try await git.subdirTreeHash(in: repo, subdir: "skills/beta")
        #expect(hashA1 != hashA2)
        #expect(hashB1 == hashB2)
    }

    @Test("subdirTreeHash with empty subdir falls back to full tree hash")
    func subdirTreeHashEmptyFallsBack() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let repo = try makeRepo(in: dir)
        let git = GitActor()
        let sub = try await git.subdirTreeHash(in: repo, subdir: "")
        let tree = try await git.treeHash(in: repo, ref: "HEAD")
        #expect(sub == tree)
    }

    @Test("proxy settings are converted to git process environment")
    func proxyEnvironment() async throws {
        let suite = "skillport-git-proxy-\(UUID())"
        let proxySettings = ProxySettingsActor(suiteName: suite)
        await proxySettings.save(
            ProxyConfig(
                enabled: true,
                kind: .socks5,
                host: "127.0.0.1",
                port: 1080,
                username: "alice",
                bypassList: ["localhost"]
            )
        )
        let env = await GitActor(proxySettings: proxySettings)
            .effectiveProxyEnvironmentForTesting(password: "secret")
        #expect(env["ALL_PROXY"] == "socks5://alice:secret@127.0.0.1:1080")
        #expect(env["NO_PROXY"] == "localhost")
    }

    private func makeSleepingGit(in dir: TempDir) throws -> URL {
        let fakeGit = dir.url.appendingPathComponent("fake-git")
        try "#!/bin/sh\nsleep 1\necho should-not-complete\n".write(
            to: fakeGit,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeGit.path
        )
        return fakeGit
    }
}
