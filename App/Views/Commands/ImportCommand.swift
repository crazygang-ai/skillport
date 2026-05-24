import AppKit
import Foundation

@MainActor
enum ImportCommand {
    /// 弹原生 NSOpenPanel 让用户选 skill 文件夹，返回所选 URL（canceled 返回 nil）。
    static func pickFolder() -> URL? {
        let strings = AppStrings.current()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = strings("Choose a skill folder")
        panel.prompt = strings("Import")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
