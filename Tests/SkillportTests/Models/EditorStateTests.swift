import Foundation
import Testing

@testable import Skillport

@Suite("EditorState")
@MainActor
struct EditorStateTests {
    @Test("saving body-only skill does not persist inferred frontmatter")
    func savingBodyOnlySkillDoesNotPersistInferredFrontmatter() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let file = try dir.write(
            "SKILL.md",
            content: "# Just body\n\nNo frontmatter at all.\n"
        )
        let state = EditorState()
        try state.load(from: file)

        state.body += "\nEdited body.\n"
        try state.save()

        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(!raw.hasPrefix("---"))
        #expect(!raw.contains("name: Just body"))
        #expect(!raw.contains("description: No frontmatter at all."))
        #expect(raw.contains("Edited body."))
    }

    @Test("saving edited metadata persists only the changed field")
    func savingEditedMetadataPersistsOnlyChangedField() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let file = try dir.write(
            "SKILL.md",
            content: "# Just body\n\nNo frontmatter at all.\n"
        )
        let state = EditorState()
        try state.load(from: file)

        state.metadata.description = "Manual description"
        try state.save()

        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(raw.hasPrefix("---"))
        #expect(raw.contains("description: Manual description"))
        #expect(!raw.contains("name: Just body"))
    }
}
