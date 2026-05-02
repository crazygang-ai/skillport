import Testing
@testable import Skillport

@Suite("AppUpdaterBridge")
@MainActor
struct AppUpdaterBridgeTests {
    @Test("Bridge initializes without feedURL (lazy / stubbed)")
    func initializesWithoutFeed() {
        let bridge = AppUpdaterBridge(feedURL: nil)
        #expect(bridge.isUpdateAvailable == false)
        #expect(bridge.latestCheckDate == nil)
    }

    @Test("Bridge exposes a stable subsystem label")
    func subsystemLabel() {
        let bridge = AppUpdaterBridge(feedURL: nil)
        #expect(bridge.subsystemLabel == "sparkle")
    }
}
