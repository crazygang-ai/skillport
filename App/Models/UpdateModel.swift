import Foundation
import Observation

@MainActor
@Observable
public final class UpdateModel {
    public private(set) var updateAvailable: Bool = false
    public private(set) var lastCheck: Date?
    public private(set) var automaticallyChecksForUpdates: Bool = false

    private let bridge: AppUpdaterBridge

    public init(bridge: AppUpdaterBridge) {
        self.bridge = bridge
        self.updateAvailable = bridge.isUpdateAvailable
        self.lastCheck = bridge.latestCheckDate
        self.automaticallyChecksForUpdates = bridge.automaticallyChecksForUpdates
        bridge.onStateChanged = { [weak self] available, lastCheck in
            self?.updateAvailable = available
            self?.lastCheck = lastCheck
        }
    }

    public func checkNow() {
        bridge.checkForUpdates()
        lastCheck = bridge.latestCheckDate
        updateAvailable = bridge.isUpdateAvailable
    }

    public func checkInformationNow() {
        bridge.checkForUpdateInformation()
        lastCheck = bridge.latestCheckDate
        updateAvailable = bridge.isUpdateAvailable
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        bridge.setAutomaticallyChecksForUpdates(enabled)
        automaticallyChecksForUpdates = bridge.automaticallyChecksForUpdates
    }
}
