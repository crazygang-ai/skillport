import Foundation

public actor ProxySettingsActor {
    private static let key = "skillport.proxy.config.v1"
    public static let proxyPasswordAccount = "proxy"
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

    public func makeSession(password: String? = nil) -> URLSession {
        NetworkSession.makeSession(proxy: current, password: password)
    }

    public func connectionProxySummary(password: String? = nil) -> [String: String] {
        NetworkSession.connectionProxySummary(proxy: current, password: password)
    }

    public func proxyEnvironment(password: String? = nil) -> [String: String] {
        NetworkSession.proxyEnvironment(proxy: current, password: password)
    }
}
