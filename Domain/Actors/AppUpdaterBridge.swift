import Foundation
import Observation
import Sparkle

/// 包装 Sparkle 的 SPUStandardUpdaterController。
/// feedURL 默认从 Info.plist 的 `SUFeedURL` 读取；若为占位符（含 "YOUR_DOMAIN"）则禁用自动检查。
@MainActor
@Observable
public final class AppUpdaterBridge {
    public private(set) var isUpdateAvailable: Bool = false
    public private(set) var latestCheckDate: Date?
    public let subsystemLabel: String = "sparkle"

    private let controller: SPUStandardUpdaterController?

    public init(feedURL: URL? = nil) {
        let effective = feedURL ?? Self.feedURLFromInfoPlist()
        if let effective {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.setFeedURL(effective)
            self.controller = controller
        } else {
            self.controller = nil
        }
    }

    public func checkForUpdates() {
        controller?.updater.checkForUpdates()
        latestCheckDate = Date()
    }

    /// Read SUFeedURL from Info.plist; return nil for placeholder or missing entries.
    private static func feedURLFromInfoPlist() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !raw.isEmpty,
            !raw.contains("YOUR_DOMAIN"),
            let url = URL(string: raw)
        else {
            return nil
        }
        return url
    }
}
