import Foundation

@testable import Skillport

enum GitFixtures {
    /// 造一个 bare git repo，根目录有 SKILL.md。
    static func makeBareRepoWithRootSKILL(under home: URL) throws -> URL {
        let workDir = home.appendingPathComponent("repo-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try "---\ndescription: test\n---\n# Root\n".write(
            to: workDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try runGit(in: workDir, ["init", "-b", "main"])
        try runGit(in: workDir, ["add", "."])
        try runGit(
            in: workDir,
            [
                "-c", "user.name=t", "-c", "user.email=t@t.t",
                "commit", "-m", "init",
            ])
        let bareURL = home.appendingPathComponent("bare-\(UUID().uuidString).git")
        try runGit(in: workDir, ["clone", "--bare", ".", bareURL.path])
        return bareURL
    }

    /// 造一个 bare repo，其中 `.claude/skills/<skill>/` 内的 assets 通过 symlink 指向 repo 内的 `src/`。
    static func makeBareRepoWithClaudeSkillSymlinkedAssets(under home: URL) throws -> URL {
        let workDir = home.appendingPathComponent("repo-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let skillDir = workDir.appendingPathComponent(".claude/skills/ui-ux-pro-max")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "---\ndescription: ui ux\n---\n# UI UX\n".write(
            to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let sourceScripts = workDir.appendingPathComponent("src/ui-ux-pro-max/scripts")
        try FileManager.default.createDirectory(at: sourceScripts, withIntermediateDirectories: true)
        try "#!/bin/sh\necho ok\n".write(
            to: sourceScripts.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)

        let sourceData = workDir.appendingPathComponent("src/ui-ux-pro-max/data")
        try FileManager.default.createDirectory(at: sourceData, withIntermediateDirectories: true)
        try "{\"ok\":true}\n".write(
            to: sourceData.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        try FileManager.default.createSymbolicLink(
            atPath: skillDir.appendingPathComponent("scripts").path,
            withDestinationPath: "../../../src/ui-ux-pro-max/scripts"
        )
        try FileManager.default.createSymbolicLink(
            atPath: skillDir.appendingPathComponent("data").path,
            withDestinationPath: "../../../src/ui-ux-pro-max/data"
        )

        try runGit(in: workDir, ["init", "-b", "main"])
        try runGit(in: workDir, ["add", "."])
        try runGit(
            in: workDir,
            [
                "-c", "user.name=t", "-c", "user.email=t@t.t",
                "commit", "-m", "init",
            ])
        let bareURL = home.appendingPathComponent("bare-\(UUID().uuidString).git")
        try runGit(in: workDir, ["clone", "--bare", ".", bareURL.path])
        return bareURL
    }

    /// 造一个 bare repo，其中 skill 内的 symlink 指向 repo 外。
    static func makeBareRepoWithEscapingSymlink(under home: URL) throws -> URL {
        let outside = home.appendingPathComponent("outside-target")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let workDir = home.appendingPathComponent("repo-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try "---\ndescription: escaping\n---\n# Root\n".write(
            to: workDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: workDir.appendingPathComponent("scripts").path,
            withDestinationPath: outside.path
        )
        try runGit(in: workDir, ["init", "-b", "main"])
        try runGit(in: workDir, ["add", "."])
        try runGit(
            in: workDir,
            [
                "-c", "user.name=t", "-c", "user.email=t@t.t",
                "commit", "-m", "init",
            ])
        let bareURL = home.appendingPathComponent("bare-\(UUID().uuidString).git")
        try runGit(in: workDir, ["clone", "--bare", ".", bareURL.path])
        return bareURL
    }

    /// 造一个 bare repo，`skills/<sub>/SKILL.md` 布局。
    static func makeBareRepoWithSubSkills(under home: URL, subs: [String]) throws -> URL {
        let workDir = home.appendingPathComponent("repo-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        for sub in subs {
            let dir = workDir.appendingPathComponent("skills/\(sub)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\ndescription: \(sub)\n---\n# \(sub)\n".write(
                to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try runGit(in: workDir, ["init", "-b", "main"])
        try runGit(in: workDir, ["add", "."])
        try runGit(
            in: workDir,
            [
                "-c", "user.name=t", "-c", "user.email=t@t.t",
                "commit", "-m", "init",
            ])
        let bareURL = home.appendingPathComponent("bare-\(UUID().uuidString).git")
        try runGit(in: workDir, ["clone", "--bare", ".", bareURL.path])
        return bareURL
    }

    /// 造一个 bare repo，根目录和 `skills/<sub>/` 同时有 SKILL.md。
    static func makeBareRepoWithRootAndSubSkills(under home: URL, subs: [String]) throws -> URL {
        let workDir = home.appendingPathComponent("repo-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try "---\ndescription: root\n---\n# Root\n".write(
            to: workDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for sub in subs {
            let dir = workDir.appendingPathComponent("skills/\(sub)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\ndescription: \(sub)\n---\n# \(sub)\n".write(
                to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try runGit(in: workDir, ["init", "-b", "main"])
        try runGit(in: workDir, ["add", "."])
        try runGit(
            in: workDir,
            [
                "-c", "user.name=t", "-c", "user.email=t@t.t",
                "commit", "-m", "init",
            ])
        let bareURL = home.appendingPathComponent("bare-\(UUID().uuidString).git")
        try runGit(in: workDir, ["clone", "--bare", ".", bareURL.path])
        return bareURL
    }

    private static func runGit(in dir: URL, _ args: [String]) throws {
        let p = Process()
        p.currentDirectoryURL = dir
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        let err = Pipe()
        let out = Pipe()
        p.standardError = err
        p.standardOutput = out
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let stderr =
                String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SkillportError.gitFailed(exitCode: p.terminationStatus, stderr: stderr)
        }
    }
}
