import Testing

@testable import Skillport

@Suite("UpdateModel")
@MainActor
struct UpdateModelTests {
    @Test("Initial state: no update available, no last check")
    func initialState() {
        let model = UpdateModel(bridge: AppUpdaterBridge(feedURL: nil))
        #expect(model.updateAvailable == false)
        #expect(model.lastCheck == nil)
    }

    @Test("checkNow forwards to bridge and records lastCheck")
    func checkNow() {
        let bridge = AppUpdaterBridge(feedURL: nil)
        let model = UpdateModel(bridge: bridge)
        model.checkNow()
        #expect(model.lastCheck != nil)
    }

    @Test("bridge update availability propagates into model")
    func bridgeStatePropagation() {
        let bridge = AppUpdaterBridge(feedURL: nil)
        let model = UpdateModel(bridge: bridge)
        bridge.recordUpdateAvailability(true)
        #expect(model.updateAvailable == true)
        bridge.recordUpdateAvailability(false)
        #expect(model.updateAvailable == false)
    }

    @Test("auto-check preference forwards to bridge")
    func autoCheckForwarding() {
        let bridge = AppUpdaterBridge(feedURL: nil)
        let model = UpdateModel(bridge: bridge)
        model.setAutomaticallyChecksForUpdates(true)
        #expect(model.automaticallyChecksForUpdates == true)
        #expect(bridge.automaticallyChecksForUpdates == true)
    }
}
