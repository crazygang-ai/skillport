import Foundation
import Testing

@testable import Skillport

@Suite("LocalImporter")
struct LocalImporterTests {
    @Test("Copies a local skill folder into canonical ~/.agents/skills")
    func copyIntoCanonical() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }

        let src = try dir.mkdir("my-skill")
        try "---\ndescription: t\n---\nbody".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )

        let home = try dir.mkdir("home")
        let importer = LocalImporter()
        let dest = try importer.importSkill(from: src, home: home)
        #expect(dest.lastPathComponent == "my-skill")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("SKILL.md").path))
    }

    @Test("Refuses a folder without SKILL.md")
    func refusesInvalid() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let src = try dir.mkdir("bad")
        let importer = LocalImporter()
        #expect(throws: SkillportError.self) {
            _ = try importer.importSkill(from: src, home: dir.url)
        }
    }

    @Test("Refuses to overwrite an existing canonical skill")
    func refusesOverwrite() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }

        let src = try dir.mkdir("demo")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let home = try dir.mkdir("home")
        let importer = LocalImporter()
        _ = try importer.importSkill(from: src, home: home)
        #expect(throws: SkillportError.self) {
            _ = try importer.importSkill(from: src, home: home)
        }
    }

    @Test("Refuses source trees containing symlinks and leaves no canonical partial")
    func refusesSymlinkSourceWithoutPartial() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }

        let src = try dir.mkdir("symlinked")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let target = try dir.write("outside.txt", content: "secret")
        try FileManager.default.createSymbolicLink(
            at: src.appendingPathComponent("linked.txt"),
            withDestinationURL: target
        )
        let home = try dir.mkdir("home")

        #expect(throws: SkillportError.self) {
            _ = try LocalImporter().importSkill(from: src, home: home)
        }

        let canonical = home.appendingPathComponent(".agents/skills/symlinked")
        #expect(!FileManager.default.fileExists(atPath: canonical.path))
    }

    @Test("Refuses dot-prefixed skill folders because scanner skips hidden canonical entries")
    func refusesHiddenSkillFolder() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }

        let src = try dir.mkdir(".hidden-skill")
        try "---\n---\n".write(
            to: src.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let home = try dir.mkdir("home")

        #expect(throws: SkillportError.self) {
            _ = try LocalImporter().importSkill(from: src, home: home)
        }

        let canonical = home.appendingPathComponent(".agents/skills/.hidden-skill")
        #expect(!FileManager.default.fileExists(atPath: canonical.path))
    }
}
