import AppKit
import Quartz

class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let label = NSTextField(labelWithString: "Skillport Preview — loading...")
        label.frame = NSRect(x: 20, y: 20, width: 400, height: 40)
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 80))
        v.addSubview(label)
        self.view = v
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        handler(nil)
    }
}
