import Foundation

@testable import Skillport

enum AgentsFS {
    /// 在 tempdir 下造一个 `~/.agents/skills/<name>/SKILL.md` 结构。
    @discardableResult
    static func createCanonicalSkill(
        in home: URL,
        name: String,
        description: String = "demo"
    ) throws -> URL {
        let skillDir =
            home
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let raw = try SKILLMdParser.serialize(
            metadata: SKILLMetadata(description: description),
            body: "# \(name)\n"
        )
        try raw.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return skillDir
    }

    /// 在某 agent 的 skills 目录下 symlink 一个 canonical skill。
    static func installSymlink(
        home: URL,
        agentRelativeSkillsDir: String,
        skillName: String
    ) throws {
        let canonical =
            home
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent(skillName)
        let linkDir = home.appendingPathComponent(agentRelativeSkillsDir, isDirectory: true)
        try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent(skillName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: canonical)
    }
}
