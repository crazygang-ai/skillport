import Foundation
import Testing

@testable import Skillport

@MainActor
@Suite("Settings end-to-end flow", .serialized)
struct SettingsFlowTests {
    @Test("apply(proxy:) round-trips via ProxySettingsActor")
    func proxyRoundtrip() async {
        let suite = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let proxyActor = ProxySettingsActor(suiteName: suite)
        let model = SettingsModel(
            proxyActor: proxyActor,
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults
        )
        var p = ProxyConfig()
        p.enabled = true
        p.host = "proxy.example.com"
        p.port = 8080
        p.kind = .https
        await model.apply(proxy: p)
        #expect(model.proxy.enabled)
        #expect(model.proxy.host == "proxy.example.com")

        // Verify actor persisted it — re-reading from a fresh actor in the same suite
        // should see the config.
        let freshActor = ProxySettingsActor(suiteName: suite)
        let roundTripped = await freshActor.current
        #expect(roundTripped.enabled == true)
        #expect(roundTripped.host == "proxy.example.com")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("autoCheckUpdates toggle survives model recreation")
    func autoCheckPersists() async {
        let suite = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let model1 = SettingsModel(
            proxyActor: ProxySettingsActor(suiteName: nil),
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults
        )
        model1.autoCheckUpdates = false
        // Recreate model reading from same defaults
        let model2 = SettingsModel(
            proxyActor: ProxySettingsActor(suiteName: nil),
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults
        )
        #expect(model2.autoCheckUpdates == false)
        defaults.removePersistentDomain(forName: suite)
    }
}
