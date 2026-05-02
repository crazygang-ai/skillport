import Foundation
import Observation
import Sparkle

/// 包装 Sparkle 的 SPUStandardUpdaterController。
/// 在 M1 阶段接受 nil feedURL 以便 app 能裸启动；
/// 实际 appcast 在 M7 milestone 接入。
@MainActor
@Observable
public final class AppUpdaterBridge {
    public private(set) var isUpdateAvailable: Bool = false
    public private(set) var latestCheckDate: Date?
    public let subsystemLabel: String = "sparkle"

    private let controller: SPUStandardUpdaterController?

    public init(feedURL: URL?) {
        if let feedURL {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.setFeedURL(feedURL)
            self.controller = controller
        } else {
            self.controller = nil
        }
    }

    public func checkForUpdates() {
        controller?.updater.checkForUpdates()
        latestCheckDate = Date()
    }
}
