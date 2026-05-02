import AppKit
import Foundation

@MainActor
enum ImportCommand {
    /// 弹原生 NSOpenPanel 让用户选 skill 文件夹，返回所选 URL（canceled 返回 nil）。
    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a skill folder"
        panel.prompt = "Import"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
