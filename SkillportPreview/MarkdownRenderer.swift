import AppKit
import Foundation
import Markdown

/// 极简 Markdown → NSAttributedString 渲染器。
/// 独立于主 app 的 RegistryContentRenderer（那是 @MainActor、返回 SwiftUI AttributedString）。
/// 扩展沙盒下只能用 AppKit，这里直接吐 NSAttributedString 给 NSTextView。
enum MarkdownRenderer {
    static func renderToAttributed(_ markdown: String) -> NSAttributedString {
        let doc = Document(parsing: markdown)
        let out = NSMutableAttributedString()
        renderChildren(of: doc, into: out, indent: 0)
        return out
    }

    private static func renderChildren(
        of node: Markup, into out: NSMutableAttributedString, indent: Int
    ) {
        for child in node.children {
            renderNode(child, into: out, indent: indent)
        }
    }

    private static func renderNode(
        _ node: Markup, into out: NSMutableAttributedString, indent: Int
    ) {
        switch node {
        case let heading as Heading:
            let size: CGFloat = max(13, CGFloat(28 - heading.level * 2))
            let s = NSMutableAttributedString(string: heading.plainText + "\n\n")
            s.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: size, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                ], range: NSRange(location: 0, length: s.length - 2))
            out.append(s)
        case let paragraph as Paragraph:
            for child in paragraph.children {
                renderInline(child, into: out)
            }
            out.append(NSAttributedString(string: "\n\n"))
        case let code as CodeBlock:
            let s = NSMutableAttributedString(string: code.code + "\n")
            s.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(
                        ofSize: NSFont.systemFontSize, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.5),
                ], range: NSRange(location: 0, length: s.length))
            out.append(s)
            out.append(NSAttributedString(string: "\n"))
        case let ul as UnorderedList:
            for item in ul.listItems {
                out.append(NSAttributedString(string: String(repeating: "  ", count: indent)))
                out.append(NSAttributedString(string: "• "))
                renderChildren(of: item, into: out, indent: indent + 1)
            }
        case let ol as OrderedList:
            var idx = 1
            for item in ol.listItems {
                out.append(NSAttributedString(string: String(repeating: "  ", count: indent)))
                out.append(NSAttributedString(string: "\(idx). "))
                renderChildren(of: item, into: out, indent: indent + 1)
                idx += 1
            }
        case let block as BlockQuote:
            let start = out.length
            renderChildren(of: block, into: out, indent: indent)
            out.addAttribute(
                .foregroundColor, value: NSColor.secondaryLabelColor,
                range: NSRange(location: start, length: out.length - start))
        case let table as Markdown.Table:
            let headerLine = table.head.cells.map { $0.plainText }.joined(separator: " | ")
            let h = NSMutableAttributedString(string: headerLine + "\n")
            h.addAttribute(
                .font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                range: NSRange(location: 0, length: headerLine.count))
            out.append(h)
            out.append(NSAttributedString(string: String(repeating: "-", count: 40) + "\n"))
            for row in table.body.rows {
                let line = row.cells.map { $0.plainText }.joined(separator: " | ")
                out.append(NSAttributedString(string: line + "\n"))
            }
            out.append(NSAttributedString(string: "\n"))
        default:
            out.append(NSAttributedString(string: node.format()))
        }
    }

    private static func renderInline(_ node: Markup, into out: NSMutableAttributedString) {
        switch node {
        case let text as Markdown.Text:
            out.append(NSAttributedString(string: text.string))
        case let code as InlineCode:
            let s = NSMutableAttributedString(string: code.code)
            s.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(
                    ofSize: NSFont.systemFontSize, weight: .regular),
                range: NSRange(location: 0, length: s.length))
            out.append(s)
        case let link as Markdown.Link:
            let s = NSMutableAttributedString(string: link.plainText)
            if let dest = link.destination, let url = URL(string: dest) {
                s.addAttribute(
                    .link, value: url, range: NSRange(location: 0, length: s.length))
            }
            out.append(s)
        case let emph as Emphasis:
            let s = NSMutableAttributedString(string: emph.plainText)
            s.addAttribute(
                .font,
                value: NSFontManager.shared.convert(
                    NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    toHaveTrait: .italicFontMask),
                range: NSRange(location: 0, length: s.length))
            out.append(s)
        case let strong as Strong:
            let s = NSMutableAttributedString(string: strong.plainText)
            s.addAttribute(
                .font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                range: NSRange(location: 0, length: s.length))
            out.append(s)
        case let image as Markdown.Image:
            let alt = image.plainText.isEmpty ? "image" : image.plainText
            let url = image.source ?? ""
            let s = NSMutableAttributedString(string: "[Image: \(alt) — \(url)]")
            s.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: NSRange(location: 0, length: s.length))
            out.append(s)
        default:
            out.append(NSAttributedString(string: node.format()))
        }
    }
}
