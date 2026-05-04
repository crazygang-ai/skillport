import Foundation
import Testing

@testable import Skillport

@Suite("SKILLMdParser")
struct SKILLMdParserTests {
    @Test("Parses frontmatter and body from standard SKILL.md")
    func parsesBasicFixture() throws {
        let url = TestBundleLocator.bundle.url(forResource: "SKILL_basic", withExtension: "md")!
        let raw = try String(contentsOf: url, encoding: .utf8)
        let result = try SKILLMdParser.parse(raw)
        #expect(result.metadata.description == "A demo skill")
        #expect(result.metadata.version == "0.1.0")
        #expect(result.metadata.allowedTools == ["Read", "Write"])
        #expect(result.body.contains("# Demo skill"))
        #expect(result.body.contains("Body paragraph here."))
    }

    @Test("No-frontmatter file extracts name + description from # heading + first paragraph")
    func handlesNoFrontmatter() throws {
        let url = TestBundleLocator.bundle.url(forResource: "SKILL_no_frontmatter", withExtension: "md")!
        let raw = try String(contentsOf: url, encoding: .utf8)
        let result = try SKILLMdParser.parse(raw)
        #expect(result.metadata.name == "Just body")
        #expect(result.metadata.description == "No frontmatter at all.")
        // body 保持完整（含标题），原文不被吞。
        #expect(result.body.hasPrefix("# Just body"))
    }

    @Test("Frontmatter-only file keeps explicit description; body fallback doesn't override")
    func frontmatterOverridesBodyFallback() throws {
        let raw = "---\ndescription: from-yaml\n---\n# Heading\n\nParagraph text.\n"
        let result = try SKILLMdParser.parse(raw)
        #expect(result.metadata.description == "from-yaml")
        // name 在 frontmatter 里没写，应从 body fallback
        #expect(result.metadata.name == "Heading")
    }

    @Test("Parser reads name/license/author/version from frontmatter")
    func parsesExtendedFields() throws {
        let raw = """
            ---
            name: MySkill
            description: d
            version: 1.2.3
            license: MIT
            author: Alice
            allowedTools: [Read, Write]
            ---
            # body
            """
        let result = try SKILLMdParser.parse(raw)
        #expect(result.metadata.name == "MySkill")
        #expect(result.metadata.license == "MIT")
        #expect(result.metadata.author == "Alice")
        #expect(result.metadata.version == "1.2.3")
        #expect(result.metadata.allowedTools == ["Read", "Write"])
    }

    @Test("Unclosed frontmatter throws parseFailed")
    func unclosedFrontmatterThrows() {
        let bad = "---\ndescription: hi\n\n# Body without closer"
        #expect(throws: SkillportError.self) {
            _ = try SKILLMdParser.parse(bad)
        }
    }

    @Test("serialize round-trips back to equivalent raw text")
    func serializeRoundTrip() throws {
        let meta = SKILLMetadata(description: "hi", version: "1.0.0", allowedTools: ["Bash"])
        let body = "# Body\n\ncontent\n"
        let raw = try SKILLMdParser.serialize(metadata: meta, body: body)
        let reparsed = try SKILLMdParser.parse(raw)
        #expect(reparsed.metadata.description == "hi")
        #expect(reparsed.metadata.version == "1.0.0")
        #expect(reparsed.metadata.allowedTools == ["Bash"])
        #expect(reparsed.body.contains("# Body"))
    }
}
