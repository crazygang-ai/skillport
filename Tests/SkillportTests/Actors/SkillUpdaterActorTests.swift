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

@Suite("SkillUpdaterActor — subdir tree hash + apply", .serialized)
struct SkillUpdaterSubdirTests {
    @Test("checkStatus returns .available when lockfile baseline diverges from current remote subdir hash")
    func availableWhenBaselineStale() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["alpha"])

        let cache = CommitHashCache(path: home.appendingPathComponent(".cache.json"))
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let lockFile = LockFileActor(path: lockPath)
        let repoCache = RepoCacheActor(
            git: GitActor(), root: dir.url.appendingPathComponent("rc"))
        let installer = SkillInstallerActor(
            git: GitActor(), symlinker: SymlinkManagerActor(),
            lockFile: lockFile, cache: cache, repoCache: repoCache
        )
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "alpha", home: home, installTo: [])

        // Simulate "remote changed since install" by overwriting lockfile baseline
        // to a fake hash — this is how checkStatus behaves when remote has new commits.
        let lock = try await lockFile.read()
        guard let orig = lock.skills.first(where: { $0.name == "alpha" }) else {
            Issue.record("expected lockfile entry"); return
        }
        let staleBaseline = LockedSkill(
            name: orig.name, source: orig.source, installedAt: orig.installedAt,
            commitHash: orig.commitHash, path: orig.path,
            skillFolderHash: "0000000000000000000000000000000000000000",
            skillPath: orig.skillPath, updatedAt: orig.updatedAt,
            dismissedUpdate: nil, lastSelectedAgents: orig.lastSelectedAgents
        )
        try await lockFile.upsert(staleBaseline)

        let updater = SkillUpdaterActor(
            git: GitActor(), cache: cache, repoCache: repoCache, lockFile: lockFile)
        let status = try await updater.checkStatus(
            name: "alpha",
            source: orig.source,
            canonical: orig.path,
            remoteURLOverride: bareRepo
        )
        if case .available = status {
            // ok
        } else {
            Issue.record("expected .available, got \(status)")
        }
    }

    @Test("checkStatus returns .upToDate when baseline matches remote subdir hash")
    func upToDateOnMatchingBaseline() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["beta"])

        let cache = CommitHashCache(path: home.appendingPathComponent(".cache.json"))
        let lockFile = LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json"))
        let repoCache = RepoCacheActor(
            git: GitActor(), root: dir.url.appendingPathComponent("rc"))
        let installer = SkillInstallerActor(
            git: GitActor(), symlinker: SymlinkManagerActor(),
            lockFile: lockFile, cache: cache, repoCache: repoCache
        )
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "beta", home: home, installTo: [])

        let updater = SkillUpdaterActor(
            git: GitActor(), cache: cache, repoCache: repoCache, lockFile: lockFile)
        let status = try await updater.checkStatus(
            name: "beta",
            source: .github(owner: "t", repo: "example", ref: "HEAD"),
            canonical: home.appendingPathComponent(".agents/skills/beta"),
            remoteURLOverride: bareRepo
        )
        #expect(status == .upToDate)
    }

    @Test("checkStatus treats dismissed remote hash as upToDate")
    func dismissedHashIsUpToDate() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["gamma"])

        let cache = CommitHashCache(path: home.appendingPathComponent(".cache.json"))
        let lockFile = LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json"))
        let repoCache = RepoCacheActor(
            git: GitActor(), root: dir.url.appendingPathComponent("rc"))
        let installer = SkillInstallerActor(
            git: GitActor(), symlinker: SymlinkManagerActor(),
            lockFile: lockFile, cache: cache, repoCache: repoCache
        )
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "gamma", home: home, installTo: [])

        // Read the real remote subdir hash, then lie about baseline but mark that hash as dismissed.
        let git = GitActor()
        let cached = try await repoCache.acquire(url: bareRepo, ref: "HEAD")
        let realHash = try await git.subdirTreeHash(in: cached, subdir: "skills/gamma")

        let lock = try await lockFile.read()
        guard let orig = lock.skills.first(where: { $0.name == "gamma" }) else {
            Issue.record("expected lockfile entry"); return
        }
        let dismissed = LockedSkill(
            name: orig.name, source: orig.source, installedAt: orig.installedAt,
            commitHash: orig.commitHash, path: orig.path,
            skillFolderHash: "stale",  // baseline mismatch
            skillPath: orig.skillPath, updatedAt: orig.updatedAt,
            dismissedUpdate: realHash,  // but user has dismissed this exact hash
            lastSelectedAgents: orig.lastSelectedAgents
        )
        try await lockFile.upsert(dismissed)

        let updater = SkillUpdaterActor(
            git: GitActor(), cache: cache, repoCache: repoCache, lockFile: lockFile)
        let status = try await updater.checkStatus(
            name: "gamma", source: orig.source, canonical: orig.path,
            remoteURLOverride: bareRepo)
        #expect(status == .upToDate)
    }

    @Test("apply rewrites canonical from cached repo atomically")
    func applyRewritesCanonical() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let bareRepo = try GitFixtures.makeBareRepoWithSubSkills(
            under: dir.url, subs: ["delta"])

        let cache = CommitHashCache(path: home.appendingPathComponent(".cache.json"))
        let lockFile = LockFileActor(path: home.appendingPathComponent(".agents/.skill-lock.json"))
        let repoCache = RepoCacheActor(
            git: GitActor(), root: dir.url.appendingPathComponent("rc"))
        let installer = SkillInstallerActor(
            git: GitActor(), symlinker: SymlinkManagerActor(),
            lockFile: lockFile, cache: cache, repoCache: repoCache
        )
        _ = try await installer.installGitHub(
            sourceURL: bareRepo, owner: "t", repo: "example", ref: "HEAD",
            skillId: "delta", home: home, installTo: [])
        let canonical = home.appendingPathComponent(".agents/skills/delta")

        // Simulate "canonical got corrupted / out of sync" — apply should restore.
        try "junk".write(
            to: canonical.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8)

        let updater = SkillUpdaterActor(
            git: GitActor(), cache: cache, repoCache: repoCache, lockFile: lockFile)
        let hash = try await updater.apply(
            name: "delta",
            source: .github(owner: "t", repo: "example", ref: "HEAD"),
            canonical: canonical,
            skillPath: "skills/delta",
            remoteURLOverride: bareRepo
        )
        #expect(hash.count == 40)

        let after = try String(
            contentsOf: canonical.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(after.contains("# delta"))  // fixture body
        #expect(!after.contains("junk"))
    }
}
