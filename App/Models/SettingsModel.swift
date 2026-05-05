import Foundation
import Observation

@MainActor
@Observable
public final class SettingsModel {
    public var proxy: ProxyConfig = ProxyConfig()
    public var preferredLocale: String
    public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Self.autoCheckKey) }
    }

    public static let autoCheckKey = "autoCheckUpdates"
    public static let appleLanguagesKey = "AppleLanguages"
    public static let keychainProxyAccount = ProxySettingsActor.proxyPasswordAccount

    private let proxyActor: ProxySettingsActor
    private let keychain: KeychainActor
    private let defaults: UserDefaults

    public init(
        proxyActor: ProxySettingsActor,
        keychain: KeychainActor = KeychainActor(),
        defaults: UserDefaults = .standard
    ) {
        self.proxyActor = proxyActor
        self.keychain = keychain
        self.defaults = defaults

        let rawLocale =
            (defaults.array(forKey: Self.appleLanguagesKey) as? [String])?.first ?? "en"
        self.preferredLocale = Self.normalizedLocale(rawLocale)

        if defaults.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckUpdates = true
            defaults.set(true, forKey: Self.autoCheckKey)
        } else {
            self.autoCheckUpdates = defaults.bool(forKey: Self.autoCheckKey)
        }

        Task { await refresh() }
    }

    public func refresh() async {
        self.proxy = await proxyActor.current
    }

    public func apply(proxy: ProxyConfig) async {
        await proxyActor.save(proxy)
        self.proxy = proxy
    }

    public func setPreferredLocale(_ locale: String) {
        let normalized = Self.normalizedLocale(locale)
        preferredLocale = normalized
        var current = defaults.array(forKey: Self.appleLanguagesKey) as? [String] ?? []
        current.removeAll { Self.normalizedLocale($0) == normalized }
        current.insert(normalized, at: 0)
        defaults.set(current, forKey: Self.appleLanguagesKey)
    }

    public static func normalizedLocale(_ locale: String) -> String {
        let normalized =
            locale
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") {
            return "zh-Hans"
        }
        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw")
            || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo")
        {
            return "zh-Hant"
        }
        if normalized.hasPrefix("ja") { return "ja" }
        if normalized.hasPrefix("en") { return "en" }
        return "en"
    }

    public func setProxyPassword(_ password: String) async throws {
        try await keychain.set(account: Self.keychainProxyAccount, password: password)
    }

    public func readProxyPassword() async throws -> String? {
        try await keychain.get(account: Self.keychainProxyAccount)
    }

    public func clearProxyPassword() async throws {
        try await keychain.remove(account: Self.keychainProxyAccount)
    }
}
