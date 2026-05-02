import Foundation
import Testing

@testable import Skillport

@Suite("SkillUpdaterActor")
struct SkillUpdaterActorTests {
    @Test("Local-source skills are always upToDate")
    func localUpToDate() async throws {
        let updater = SkillUpdaterActor(
            git: GitActor(),
            cache: CommitHashCache(path: URL(fileURLWithPath: "/tmp/x"))
        )
        let status = try await updater.checkStatus(
            name: "x",
            source: .local(path: URL(fileURLWithPath: "/x")),
            canonical: URL(fileURLWithPath: "/x")
        )
        #expect(status == .upToDate)
    }

    @Test("GitHub skill with cached commit equal to local HEAD is upToDate")
    func githubUpToDate() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        // 造一个带一个 commit 的 repo 当 canonical
        let repo = try dir.mkdir("repo")
        _ = try shell("git init -b main", cwd: repo)
        _ = try shell("git config user.email t@t; git config user.name t", cwd: repo)
        try "x".write(
            to: repo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try shell("git add . && git commit -m init", cwd: repo)
        let head = try shell("git rev-parse HEAD", cwd: repo).trimmingCharacters(
            in: .whitespacesAndNewlines)

        let cache = CommitHashCache(path: dir.url.appendingPathComponent("c.json"))
        let id = SkillIdentity.compute(name: "r", source: .github(owner: "o", repo: "r", ref: "main"))
        try await cache.set(identity: id, hash: head)

        let updater = SkillUpdaterActor(git: GitActor(), cache: cache)
        let status = try await updater.checkStatus(
            name: "r",
            source: .github(owner: "o", repo: "r", ref: "main"),
            canonical: repo
        )
        // 无法访问真实 remote，所以当 remote 查询失败时回退到 cached == head => .upToDate
        #expect(status == .upToDate)
    }

    @discardableResult
    private func shell(_ cmd: String, cwd: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
