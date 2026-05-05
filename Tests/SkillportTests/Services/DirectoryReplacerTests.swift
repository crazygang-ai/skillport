import Foundation
import Testing

@testable import Skillport

@Suite("DirectoryReplacer")
struct DirectoryReplacerTests {
    @Test("replace existing directory keeps rollback backup until commit")
    func replaceExistingKeepsBackupUntilCommit() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let dest = try dir.mkdir("skill")
        try "old".write(
            to: dest.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let staged = try dir.mkdir("staged")
        try "new".write(
            to: staged.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let replacement = try DirectoryReplacer.replaceDirectory(
            at: dest,
            withStagedDirectory: staged
        )

        #expect(replacement.backup != nil)
        #expect(FileManager.default.fileExists(atPath: replacement.backup?.path ?? ""))
        #expect(try skillBody(at: dest) == "new")

        try replacement.rollback()

        #expect(try skillBody(at: dest) == "old")
        #expect(!FileManager.default.fileExists(atPath: replacement.backup?.path ?? ""))
    }

    @Test("commit removes the replacement backup")
    func commitRemovesBackup() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let dest = try dir.mkdir("skill")
        try "old".write(
            to: dest.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let staged = try dir.mkdir("staged")
        try "new".write(
            to: staged.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let replacement = try DirectoryReplacer.replaceDirectory(
            at: dest,
            withStagedDirectory: staged
        )
        try replacement.commit()

        #expect(try skillBody(at: dest) == "new")
        #expect(!FileManager.default.fileExists(atPath: replacement.backup?.path ?? ""))
    }

    @Test("rollback removes new destination when no prior directory existed")
    func rollbackRemovesNewDestination() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let dest = dir.url.appendingPathComponent("skill", isDirectory: true)
        let staged = try dir.mkdir("staged")
        try "new".write(
            to: staged.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let replacement = try DirectoryReplacer.replaceDirectory(
            at: dest,
            withStagedDirectory: staged
        )
        try replacement.rollback()

        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("stageRemoveDirectory moves destination aside until commit")
    func stageRemoveCommit() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let dest = try dir.mkdir("skill")
        try "old".write(
            to: dest.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let removal = try #require(try DirectoryReplacer.stageRemoveDirectory(at: dest))

        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(FileManager.default.fileExists(atPath: removal.staged.path))

        try removal.commit()

        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: removal.staged.path))
    }

    @Test("stageRemoveDirectory can roll back the staged removal")
    func stageRemoveRollback() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let dest = try dir.mkdir("skill")
        try "old".write(
            to: dest.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let removal = try #require(try DirectoryReplacer.stageRemoveDirectory(at: dest))
        try removal.rollback()

        #expect(try skillBody(at: dest) == "old")
        #expect(!FileManager.default.fileExists(atPath: removal.staged.path))
    }

    private func skillBody(at url: URL) throws -> String {
        try String(contentsOf: url.appendingPathComponent("SKILL.md"), encoding: .utf8)
    }
}
