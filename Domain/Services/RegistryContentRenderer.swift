import AppKit
import Foundation
import Markdown
import SwiftUI

public enum RegistryRendered: Sendable {
    case empty(reason: String)
    case markdown(AttributedString)
    case attributed(AttributedString)
}

@MainActor
public struct RegistryContentRenderer {
    private let sanitizer: HTMLSanitizer
    private static let htmlPrefix = "<!-- HTML -->"
    private static let frontmatterPattern = #"\A---\r?\n[\s\S]*?\r?\n---\r?\n?"#

    public init(sanitizer: HTMLSanitizer = HTMLSanitizer()) {
        self.sanitizer = sanitizer
    }

    public func render(
        _ raw: String,
        emptyMessage: String = "No documentation available"
    ) throws -> RegistryRendered {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty(reason: emptyMessage) }

        if trimmed.hasPrefix(Self.htmlPrefix) {
            let body = String(trimmed.dropFirst(Self.htmlPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitized = try sanitizer.sanitize(body)
            if sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .empty(reason: emptyMessage)
            }
            let attributed = try renderHTMLToAttributed(sanitized)
            return .attributed(AttributedString(attributed))
        }

        let stripped = try stripFrontmatter(trimmed)
        if stripped.isEmpty { return .empty(reason: emptyMessage) }
        let doc = Document(parsing: stripped)
        let md = renderMarkdown(doc)
        return .markdown(md)
    }

    // MARK: - HTML → NSAttributedString (main thread)

    private func renderHTMLToAttributed(_ html: String) throws -> NSAttributedString {
        guard let data = html.data(using: .utf8) else {
            throw SkillportError.parseFailed(file: nil, reason: "utf8 encode failed")
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    // MARK: - Frontmatter

    private func stripFrontmatter(_ s: String) throws -> String {
        let regex = try NSRegularExpression(pattern: Self.frontmatterPattern)
        let range = NSRange(location: 0, length: (s as NSString).length)
        let replaced = regex.stringByReplacingMatches(
            in: s, options: [], range: range, withTemplate: ""
        )
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Markdown → AttributedString

    /// 极简渲染 — 递归遍历 Markup 节点, 为各类型节点附加字体/样式。
    private func renderMarkdown(_ markup: Markup) -> AttributedString {
        var acc = AttributedString()
        for child in markup.children {
            acc.append(renderNode(child, indent: 0))
        }
        return acc
    }

    private func renderNode(_ node: Markup, indent: Int = 0) -> AttributedString {
        switch node {
        case let heading as Heading:
            var s = AttributedString(heading.plainText)
            s.font = .system(
                size: CGFloat(28 - min(heading.level, 6) * 2), weight: .bold)
            s.append(AttributedString("\n\n"))
            return s
        case let paragraph as Paragraph:
            var acc = AttributedString()
            for child in paragraph.children {
                acc.append(renderInline(child))
            }
            acc.append(AttributedString("\n"))
            return acc
        case let code as CodeBlock:
            var s = AttributedString(code.code)
            s.font = .system(.body, design: .monospaced)
            s.append(AttributedString("\n\n"))
            return s
        case let ul as UnorderedList:
            var acc = AttributedString()
            for item in ul.listItems {
                acc.append(AttributedString(String(repeating: "  ", count: indent)))
                acc.append(AttributedString("• "))
                for child in item.children {
                    acc.append(renderNode(child, indent: indent + 1))
                }
            }
            return acc
        case let ol as OrderedList:
            var acc = AttributedString()
            var idx = 1
            for item in ol.listItems {
                acc.append(AttributedString(String(repeating: "  ", count: indent)))
                acc.append(AttributedString("\(idx). "))
                for child in item.children {
                    acc.append(renderNode(child, indent: indent + 1))
                }
                idx += 1
            }
            return acc
        case let block as BlockQuote:
            var acc = AttributedString()
            for child in block.children {
                acc.append(renderNode(child, indent: indent))
            }
            return acc
        case let table as Markdown.Table:
            var acc = AttributedString()
            let headerLine = table.head.cells.map { $0.plainText }.joined(separator: " | ")
            var headerText = AttributedString(headerLine)
            headerText.font = .system(.body, weight: .bold)
            acc.append(headerText)
            acc.append(AttributedString("\n"))
            acc.append(AttributedString(String(repeating: "-", count: 40) + "\n"))
            for row in table.body.rows {
                acc.append(
                    AttributedString(
                        row.cells.map { $0.plainText }.joined(separator: " | ")))
                acc.append(AttributedString("\n"))
            }
            acc.append(AttributedString("\n"))
            return acc
        default:
            return AttributedString(node.format())
        }
    }

    private func renderInline(_ node: Markup) -> AttributedString {
        switch node {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case let inlineCode as InlineCode:
            var s = AttributedString(inlineCode.code)
            s.font = .system(.body, design: .monospaced)
            return s
        case let link as Markdown.Link:
            var s = AttributedString(link.plainText)
            if let dest = link.destination, let url = URL(string: dest) {
                s.link = url
            }
            return s
        case let emph as Emphasis:
            var s = AttributedString(emph.plainText)
            s.font = .system(.body).italic()
            return s
        case let strong as Strong:
            var s = AttributedString(strong.plainText)
            s.font = .system(.body, weight: .bold)
            return s
        case let image as Markdown.Image:
            let alt = image.plainText.isEmpty ? "image" : image.plainText
            let url = image.source ?? ""
            var s = AttributedString("[Image: \(alt) — \(url)]")
            s.font = .system(.caption, weight: .regular)
            s.foregroundColor = .secondary
            return s
        default:
            return AttributedString(node.format())
        }
    }
}
