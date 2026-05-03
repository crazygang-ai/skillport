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
    public static let keychainProxyAccount = "proxy"

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

        if let arr = defaults.array(forKey: Self.appleLanguagesKey) as? [String],
            let first = arr.first, !first.isEmpty
        {
            self.preferredLocale = first
        } else {
            self.preferredLocale = "en"
        }

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
        preferredLocale = locale
        var current = defaults.array(forKey: Self.appleLanguagesKey) as? [String] ?? []
        current.removeAll { $0 == locale }
        current.insert(locale, at: 0)
        defaults.set(current, forKey: Self.appleLanguagesKey)
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
