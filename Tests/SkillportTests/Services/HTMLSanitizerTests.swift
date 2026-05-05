import Foundation
import Testing

@testable import Skillport

@Suite("HTMLSanitizer — allowlist")
struct HTMLSanitizerTests {
    let sanitizer = HTMLSanitizer()

    @Test("strips script tags")
    func stripsScript() throws {
        let out = try sanitizer.sanitize("<p>safe</p><script>alert(1)</script>")
        #expect(out.contains("<p>safe</p>"))
        #expect(!out.contains("<script"))
        #expect(!out.contains("alert"))
    }

    @Test("strips style tags and inline style attribute")
    func stripsStyle() throws {
        let out = try sanitizer.sanitize(#"<p style="color:red">x</p><style>body{}</style>"#)
        #expect(!out.contains("<style"))
        #expect(!out.contains("color:red"))
        #expect(out.contains("<p>"))
    }

    @Test("strips iframe / object / embed")
    func stripsDangerousTags() throws {
        let out = try sanitizer.sanitize("<iframe src=evil></iframe><object></object><embed>")
        #expect(!out.contains("iframe"))
        #expect(!out.contains("object"))
        #expect(!out.contains("embed"))
    }

    @Test("allows common markdown-ish tags")
    func allowsMarkdownTags() throws {
        let html =
            "<h1>t</h1><p>p</p><ul><li>x</li></ul><pre><code>y</code></pre><blockquote>q</blockquote>"
        let out = try sanitizer.sanitize(html)
        for tag in ["h1", "p", "ul", "li", "pre", "code", "blockquote"] {
            #expect(out.contains("<\(tag)"), "missing tag \(tag) in \(out)")
        }
    }

    @Test("drops javascript: urls")
    func dropsJavascriptUrl() throws {
        let out = try sanitizer.sanitize(#"<a href="javascript:alert(1)">x</a>"#)
        #expect(!out.lowercased().contains("javascript:"))
    }

    @Test("drops data: urls")
    func dropsDataUrl() throws {
        let out = try sanitizer.sanitize(#"<a href="data:text/html,evil">y</a>"#)
        #expect(!out.lowercased().contains("data:text"))
    }

    @Test("preserves https / mailto / tel / relative urls")
    func preservesSafeUrls() throws {
        let cases: [(String, String)] = [
            (#"<a href="https://a.com">a</a>"#, "https://a.com"),
            (#"<a href="mailto:x@y.z">b</a>"#, "mailto:x@y.z"),
            (#"<a href="tel:+1">c</a>"#, "tel:+1"),
            (##"<a href="#section">d</a>"##, "#section"),
            (#"<a href="/relative">e</a>"#, "/relative"),
        ]
        for (input, expected) in cases {
            let out = try sanitizer.sanitize(input)
            #expect(out.contains(expected), "\(input) → \(out)")
        }
    }

    @Test("adds rel=noopener noreferrer to anchors")
    func anchorsGetRel() throws {
        let out = try sanitizer.sanitize(#"<a href="https://a.com">x</a>"#)
        #expect(out.contains("noopener"))
        #expect(out.contains("noreferrer"))
    }

    @Test("adds empty alt to images missing alt attribute")
    func imgAltFilled() throws {
        let out = try sanitizer.sanitize(#"<img src="https://a.com/i.png">"#)
        #expect(out.contains("alt="))
    }
}
