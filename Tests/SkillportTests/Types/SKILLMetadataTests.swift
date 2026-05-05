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

    @Test("Real-world kebab-case and nested metadata fields decode")
    func realWorldDecode() throws {
        let yaml = """
            description: Browser automation
            allowed-tools: Bash(agent-browser:*), Bash(npx agent-browser:*)
            metadata:
              author: vercel
              version: "1.0.0"
              argument-hint: <file-or-pattern>
            hidden: true
            """

        let meta = try SKILLMetadata.fromYAML(yaml)

        #expect(meta.description == "Browser automation")
        #expect(meta.version == "1.0.0")
        #expect(meta.author == "vercel")
        #expect(meta.allowedTools == ["Bash(agent-browser:*)", "Bash(npx agent-browser:*)"])
        #expect(meta.extras["hidden"] as? Bool == true)
        let nested = meta.extras["metadata"] as? [String: Any]
        #expect(nested?["argument-hint"] as? String == "<file-or-pattern>")
        #expect(nested?["version"] == nil)
        #expect(nested?["author"] == nil)
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
        #expect(yaml.contains("allowed-tools"))
        #expect(yaml.contains("metadata"))
        #expect(!yaml.contains("allowedTools"))
        let back = try SKILLMetadata.fromYAML(yaml)
        #expect(back.description == "hello")
        #expect(back.version == "0.1.0")
        #expect(back.allowedTools == ["Bash"])
    }
}
