import AppKit
import Quartz

class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        scrollView.frame = v.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        textView.frame = scrollView.contentView.bounds
        textView.autoresizingMask = .width
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.font = NSFont.systemFont(ofSize: 13)

        scrollView.documentView = textView
        v.addSubview(scrollView)
        self.view = v
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let parsed =
                url.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame
                ? try? SKILLMdParser.parse(raw)
                : nil
            let body = parsed?.body ?? raw

            let attr = NSMutableAttributedString()
            if let desc = parsed?.metadata.description, !desc.isEmpty {
                let d = NSMutableAttributedString(string: "\(desc)\n\n")
                d.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ], range: NSRange(location: 0, length: d.length - 2))
                attr.append(d)
            }
            let rendered = MarkdownRenderer.renderToAttributed(body)
            attr.append(rendered)
            textView.textStorage?.setAttributedString(attr)
            handler(nil)
        } catch {
            let err = NSAttributedString(string: "Failed to preview: \(error)")
            textView.textStorage?.setAttributedString(err)
            handler(error)
        }
    }
}
