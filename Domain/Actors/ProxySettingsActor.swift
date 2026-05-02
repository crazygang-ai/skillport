import Foundation

public actor ProxySettingsActor {
    private static let key = "skillport.proxy.config.v1"
    private let defaults: UserDefaults
    public private(set) var current: ProxyConfig

    public init(suiteName: String? = nil) {
        let store: UserDefaults
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            store = suite
        } else {
            store = .standard
        }
        self.defaults = store
        if let data = store.data(forKey: Self.key),
            let cfg = try? JSONDecoder().decode(ProxyConfig.self, from: data)
        {
            self.current = cfg
        } else {
            self.current = .disabled
        }
    }

    public func save(_ config: ProxyConfig) {
        current = config
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
