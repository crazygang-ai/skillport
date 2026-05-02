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
}
