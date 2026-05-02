import Foundation
import Observation

@MainActor
@Observable
public final class UpdateModel {
    public private(set) var updateAvailable: Bool = false
    public private(set) var lastCheck: Date?

    private let bridge: AppUpdaterBridge

    public init(bridge: AppUpdaterBridge) {
        self.bridge = bridge
    }

    public func checkNow() {
        bridge.checkForUpdates()
        lastCheck = bridge.latestCheckDate
        updateAvailable = bridge.isUpdateAvailable
    }
}
