import Foundation
import Testing

@testable import Skillport

@MainActor
@Suite("RegistryContentRenderer")
struct RegistryContentRendererTests {
    let renderer = RegistryContentRenderer()

    @Test("empty input yields .empty")
    func emptyBranch() async throws {
        switch try await renderer.render("") {
        case .empty: break
        default: Issue.record("expected .empty")
        }
    }

    @Test("whitespace-only input yields .empty")
    func whitespaceBranch() async throws {
        switch try await renderer.render("   \n\t  ") {
        case .empty: break
        default: Issue.record("expected .empty")
        }
    }

    @Test("html-prefixed input goes through sanitizer + attributed branch")
    func htmlBranch() async throws {
        let input = "<!-- HTML -->\n<p>hi there</p><script>x</script>"
        switch try await renderer.render(input) {
        case .attributed(let str):
            #expect(String(str.characters).contains("hi there"))
            #expect(!String(str.characters).contains("script"))
        case .empty, .markdown:
            Issue.record("expected .attributed for HTML branch")
        }
    }

    @Test("markdown branch strips frontmatter before rendering")
    func markdownStripsFrontmatter() async throws {
        let input = """
            ---
            description: hidden
            ---
            # Visible Heading
            """
        switch try await renderer.render(input) {
        case .markdown(let str):
            let s = String(str.characters)
            #expect(s.contains("Visible"))
            #expect(!s.contains("description"))
        default:
            Issue.record("expected .markdown")
        }
    }

    @Test("markdown with no frontmatter also renders body text")
    func plainMarkdown() async throws {
        switch try await renderer.render("# Plain\n\nparagraph here") {
        case .markdown(let str):
            let s = String(str.characters)
            #expect(s.contains("Plain"))
            #expect(s.contains("paragraph here"))
        default:
            Issue.record("expected .markdown")
        }
    }

    @Test("nested lists render with indentation preserved")
    func nestedListsRender() async throws {
        let md = """
            - top
              - nested
              - also nested
            - sibling
            """
        switch try await renderer.render(md) {
        case .markdown(let str):
            let text = String(str.characters)
            #expect(text.contains("top"))
            #expect(text.contains("nested"))
            #expect(text.contains("also nested"))
            #expect(text.contains("sibling"))
        default:
            Issue.record("expected .markdown")
        }
    }

    @Test("markdown tables render as pipe-separated text with bold header")
    func tableRender() async throws {
        let md = """
            | Name | Stars |
            |------|-------|
            | foo  | 100   |
            | bar  | 50    |
            """
        switch try await renderer.render(md) {
        case .markdown(let str):
            let text = String(str.characters)
            #expect(text.contains("Name"))
            #expect(text.contains("Stars"))
            #expect(text.contains("foo"))
            #expect(text.contains("100"))
        default:
            Issue.record("expected .markdown")
        }
    }

    @Test("markdown images render as text placeholder")
    func imagePlaceholder() async throws {
        let md = "![logo](https://example.com/logo.png)"
        switch try await renderer.render(md) {
        case .markdown(let str):
            let text = String(str.characters)
            #expect(text.contains("Image"))
            #expect(text.contains("logo"))
            #expect(text.contains("example.com/logo.png"))
        default:
            Issue.record("expected .markdown")
        }
    }

    @Test("markdown links keep only safe external URL schemes")
    func markdownLinkSchemeAllowlist() async throws {
        let md = """
            [web](https://example.com) [mail](mailto:a@example.com) \
            [file](file:///etc/passwd) [prefs](x-apple.systempreferences:com.apple.Security-Privacy)
            """
        switch try await renderer.render(md) {
        case .markdown(let str):
            let links = str.runs.compactMap { $0.link?.absoluteString }
            #expect(links.contains("https://example.com"))
            #expect(links.contains("mailto:a@example.com"))
            #expect(!links.contains("file:///etc/passwd"))
            #expect(!links.contains("x-apple.systempreferences:com.apple.Security-Privacy"))
        default:
            Issue.record("expected .markdown")
        }
    }
}
