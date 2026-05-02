import Foundation
import Observation

@MainActor
@Observable
public final class SettingsModel {
    public var proxy: ProxyConfig = .disabled
    public var locale: String = "en"

    private let proxyActor: ProxySettingsActor

    public init(proxyActor: ProxySettingsActor) {
        self.proxyActor = proxyActor
        Task { await refresh() }
    }

    public func refresh() async {
        self.proxy = await proxyActor.current
    }

    public func apply(proxy: ProxyConfig) async {
        await proxyActor.save(proxy)
        self.proxy = proxy
    }
}
