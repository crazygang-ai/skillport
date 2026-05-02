import Foundation
import Testing

@testable import Skillport

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {
    @Test("Loads initial ProxyConfig from actor")
    func loadsInitial() async throws {
        let suiteName = "skillport-settings-\(UUID())"
        let actor = ProxySettingsActor(suiteName: suiteName)
        await actor.save(ProxyConfig(enabled: true, kind: .https, host: "h", port: 8080))
        let model = SettingsModel(proxyActor: actor)
        await model.refresh()
        #expect(model.proxy.enabled == true)
        #expect(model.proxy.host == "h")
    }

    @Test("apply saves through actor")
    func apply() async throws {
        let suiteName = "skillport-settings-\(UUID())"
        let actor = ProxySettingsActor(suiteName: suiteName)
        let model = SettingsModel(proxyActor: actor)
        let new = ProxyConfig(enabled: true, kind: .socks5, host: "1.2.3.4", port: 1080)
        await model.apply(proxy: new)
        let stored = await actor.current
        #expect(stored == new)
        #expect(model.proxy == new)
    }
}
