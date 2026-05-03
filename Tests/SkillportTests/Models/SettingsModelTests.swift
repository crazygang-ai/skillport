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

@Suite("SettingsModel — M6 extensions", .serialized)
@MainActor
struct SettingsModelM6Tests {
    @Test("preferredLocale reads from AppleLanguages[0] when present")
    func localeFromAppleLanguages() async {
        let suite = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["ja", "en"], forKey: "AppleLanguages")
        let model = SettingsModel(
            proxyActor: ProxySettingsActor(suiteName: nil),
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults
        )
        #expect(model.preferredLocale == "ja")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("setPreferredLocale writes AppleLanguages array into UserDefaults")
    func persistLocale() async {
        let suite = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let model = SettingsModel(
            proxyActor: ProxySettingsActor(suiteName: nil),
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults
        )
        model.setPreferredLocale("zh-Hans")
        #expect(model.preferredLocale == "zh-Hans")
        let arr = defaults.array(forKey: "AppleLanguages") as? [String] ?? []
        #expect(arr.first == "zh-Hans")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("autoCheckUpdates default true; toggling persists")
    func autoCheckDefault() async {
        let suite = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let model = SettingsModel(
            proxyActor: ProxySettingsActor(suiteName: nil),
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults
        )
        #expect(model.autoCheckUpdates == true)
        model.autoCheckUpdates = false
        #expect(defaults.bool(forKey: "autoCheckUpdates") == false)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("setProxyPassword stores in Keychain; readProxyPassword retrieves")
    func keychainRoundtrip() async throws {
        let svc = "skillport-test-\(UUID())"
        let kc = KeychainActor(service: svc)
        let suite = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let model = SettingsModel(
            proxyActor: ProxySettingsActor(suiteName: nil),
            keychain: kc,
            defaults: defaults
        )
        try await model.setProxyPassword("sekret")
        let read = try await model.readProxyPassword()
        #expect(read == "sekret")
        try? await kc.remove(account: "proxy")
        defaults.removePersistentDomain(forName: suite)
    }
}
