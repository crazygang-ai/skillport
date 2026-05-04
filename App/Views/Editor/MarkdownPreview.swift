import Markdown
import SwiftUI

/// 把 Markdown 源按块级元素（heading / paragraph / code block / list）拆成独立
/// SwiftUI 子视图在 VStack 里渲染。这是相对 `Text(AttributedString)` 一次性渲染
/// 的可靠方案——后者在 SwiftUI 里会把不同风格的 run 压成一段（看起来像字号/粗体
/// 全丢、换行全吞），无法满足 skill SKILL.md 那种长文排版。
struct MarkdownPreview: View {
    let source: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let doc = Document(parsing: source)
                ForEach(Array(doc.children.enumerated()), id: \.offset) { _, node in
                    BlockView(node: node, indent: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
    }
}

// MARK: - 块级

private struct BlockView: View {
    let node: Markup
    let indent: Int

    var body: some View {
        switch node {
        case let heading as Heading:
            Text(inlineAttributed(heading.children))
                .font(.system(size: headingSize(heading.level), weight: .bold))
                .padding(.top, heading.level == 1 ? 4 : 2)
                .padding(.bottom, 2)

        case let paragraph as Paragraph:
            Text(inlineAttributed(paragraph.children))
                .fixedSize(horizontal: false, vertical: true)

        case let code as CodeBlock:
            Text(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
                .textSelection(.enabled)

        case let ul as UnorderedList:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(ul.listItems.enumerated()), id: \.offset) { _, item in
                    ListItemView(item: item, marker: "•", indent: indent)
                }
            }

        case let ol as OrderedList:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(ol.listItems.enumerated()), id: \.offset) { idx, item in
                    ListItemView(item: item, marker: "\(idx + 1).", indent: indent)
                }
            }

        case let blockQuote as BlockQuote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                        BlockView(node: child, indent: indent)
                    }
                }
            }
            .foregroundStyle(.secondary)

        case let table as Markdown.Table:
            TableView(table: table)

        case is ThematicBreak:
            Divider()

        default:
            // 未知节点回退为 raw source（保留原文而不是丢）
            Text(node.format())
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 20
        case 3: return 17
        case 4: return 15
        default: return 14
        }
    }
}

private struct ListItemView: View {
    let item: ListItem
    let marker: String
    let indent: Int

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.body)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    BlockView(node: child, indent: indent + 1)
                }
            }
        }
        .padding(.leading, CGFloat(indent) * 14)
    }
}

private struct TableView: View {
    let table: Markdown.Table

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(table.head.cells.enumerated()), id: \.offset) { _, cell in
                    Text(cell.plainText)
                        .font(.body.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            // Rows
            ForEach(Array(table.body.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell.plainText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - inline → AttributedString

private func inlineAttributed(_ children: MarkupChildren) -> AttributedString {
    var acc = AttributedString()
    for child in children {
        acc.append(renderInline(child))
    }
    return acc
}

private func renderInline(_ node: Markup) -> AttributedString {
    switch node {
    case let text as Markdown.Text:
        return AttributedString(text.string)

    case let code as InlineCode:
        var s = AttributedString(code.code)
        s.font = .system(.body, design: .monospaced)
        s.backgroundColor = .secondary.opacity(0.12)
        return s

    case let link as Markdown.Link:
        var s = inlineAttributed(link.children)
        if let dest = link.destination, let url = URL(string: dest) {
            s.link = url
            s.foregroundColor = .accentColor
        }
        return s

    case let emph as Emphasis:
        var s = inlineAttributed(emph.children)
        s.font = .system(.body).italic()
        return s

    case let strong as Strong:
        var s = inlineAttributed(strong.children)
        s.font = .system(.body, weight: .bold)
        return s

    case let image as Markdown.Image:
        let alt = image.plainText.isEmpty ? "image" : image.plainText
        let url = image.source ?? ""
        var s = AttributedString("[Image: \(alt) — \(url)]")
        s.font = .system(.caption)
        s.foregroundColor = .secondary
        return s

    case is LineBreak, is SoftBreak:
        return AttributedString(" ")

    default:
        return AttributedString(node.format())
    }
}
