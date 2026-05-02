import Testing

@testable import Skillport

@Suite("AppModel")
@MainActor
struct AppModelTests {
    @Test("Default section is dashboard")
    func defaultSection() {
        let app = AppModel()
        #expect(app.section == .dashboard)
        #expect(app.currentAgentFilter == nil)
    }

    @Test("setSection updates state")
    func setSection() {
        let app = AppModel()
        app.setSection(.registry)
        #expect(app.section == .registry)
    }

    @Test("selectAgent toggles filter; nil clears")
    func selectAgent() {
        let app = AppModel()
        app.selectAgent(.claudeCode)
        #expect(app.currentAgentFilter == .claudeCode)
        app.selectAgent(nil)
        #expect(app.currentAgentFilter == nil)
    }
}
