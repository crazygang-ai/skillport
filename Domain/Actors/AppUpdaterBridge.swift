import Foundation
import Observation
import Sparkle

/// 包装 Sparkle 的 SPUStandardUpdaterController。
/// feedURL 默认从 Info.plist 的 `SUFeedURL` 读取；若为占位符（含 "YOUR_DOMAIN"）则禁用自动检查。
@MainActor
@Observable
public final class AppUpdaterBridge: NSObject, SPUUpdaterDelegate {
    public private(set) var isUpdateAvailable: Bool = false
    public private(set) var latestCheckDate: Date?
    public private(set) var automaticallyChecksForUpdates: Bool = false
    public let subsystemLabel: String = "sparkle"

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored public var onStateChanged: (@MainActor @Sendable (Bool, Date?) -> Void)?
    private let feedURLString: String?

    public init(feedURL: URL? = nil) {
        let effective = feedURL ?? Self.feedURLFromInfoPlist()
        self.feedURLString = effective?.absoluteString
        super.init()
        if feedURLString != nil {
            self.controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            self.automaticallyChecksForUpdates =
                self.controller?.updater.automaticallyChecksForUpdates ?? false
        } else {
            self.controller = nil
        }
    }

    public func checkForUpdates() {
        controller?.updater.checkForUpdates()
        latestCheckDate = Date()
        publishState()
    }

    public func checkForUpdateInformation() {
        controller?.updater.checkForUpdateInformation()
        latestCheckDate = Date()
        publishState()
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        controller?.updater.automaticallyChecksForUpdates = enabled
        publishState()
    }

    func recordUpdateAvailability(_ available: Bool) {
        isUpdateAvailable = available
        publishState()
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordUpdateAvailability(true)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        recordUpdateAvailability(false)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        recordUpdateAvailability(false)
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

    @objc(feedURLStringForUpdater:)
    public func feedURLString(for _: SPUUpdater) -> String? {
        feedURLString
    }

    private func publishState() {
        onStateChanged?(isUpdateAvailable, latestCheckDate)
    }
}
