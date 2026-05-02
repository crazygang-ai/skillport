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

    @Test("No-frontmatter file yields empty metadata and full body")
    func handlesNoFrontmatter() throws {
        let url = TestBundleLocator.bundle.url(forResource: "SKILL_no_frontmatter", withExtension: "md")!
        let raw = try String(contentsOf: url, encoding: .utf8)
        let result = try SKILLMdParser.parse(raw)
        #expect(result.metadata.description == nil)
        #expect(result.body.hasPrefix("# Just body"))
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
