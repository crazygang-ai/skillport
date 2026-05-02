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
}
