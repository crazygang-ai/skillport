import Testing
@testable import Skillport

@Suite("SKILLMetadata")
struct SKILLMetadataTests {
    @Test("Empty frontmatter decodes with nil optionals")
    func emptyDecode() throws {
        let yaml = ""
        let meta = try SKILLMetadata.fromYAML(yaml)
        #expect(meta.description == nil)
        #expect(meta.version == nil)
        #expect(meta.allowedTools == nil)
        #expect(meta.extras.isEmpty)
    }

    @Test("Standard frontmatter decodes known fields + preserves unknowns in extras")
    func standardDecode() throws {
        let yaml = """
            description: A superpowers skill
            version: 1.2.3
            allowedTools: ["Read", "Write"]
            custom_field: custom_value
            """
        let meta = try SKILLMetadata.fromYAML(yaml)
        #expect(meta.description == "A superpowers skill")
        #expect(meta.version == "1.2.3")
        #expect(meta.allowedTools == ["Read", "Write"])
        #expect(meta.extras["custom_field"] as? String == "custom_value")
    }

    @Test("toYAML round-trips description and version")
    func yamlRoundTrip() throws {
        let meta = SKILLMetadata(
            description: "hello",
            version: "0.1.0",
            allowedTools: ["Bash"],
            extras: [:]
        )
        let yaml = try meta.toYAML()
        let back = try SKILLMetadata.fromYAML(yaml)
        #expect(back.description == "hello")
        #expect(back.version == "0.1.0")
        #expect(back.allowedTools == ["Bash"])
    }
}
