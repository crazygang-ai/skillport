import Foundation
import Testing

@testable import Skillport

@Suite("ProxyConfig")
struct ProxyConfigTests {
    @Test("Codable round-trip preserves bypassList")
    func codableRoundTrip() throws {
        let original = ProxyConfig(
            enabled: true,
            kind: .https,
            host: "proxy.example",
            port: 8080,
            username: "u",
            bypassList: ["*.internal", "10.*"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyConfig.self, from: data)
        #expect(decoded == original)
        #expect(decoded.bypassList == ["*.internal", "10.*"])
    }

    @Test("NetworkSession makeSession applies bypassList to connectionProxyDictionary")
    func bypassListApplied() {
        let config = ProxyConfig(
            enabled: true, kind: .https, host: "proxy", port: 1234,
            bypassList: ["*.internal"]
        )
        let session = NetworkSession.makeSession(proxy: config)
        let dict = session.configuration.connectionProxyDictionary ?? [:]
        let bypass = dict[kCFNetworkProxiesExceptionsList as AnyHashable] as? [String]
        #expect(bypass == ["*.internal"])
    }

    @Test("NetworkSession drops proxy dict entirely when proxy disabled")
    func disabledProxyDict() {
        let config = ProxyConfig(enabled: false)
        let session = NetworkSession.makeSession(proxy: config)
        #expect(session.configuration.connectionProxyDictionary?.isEmpty ?? true)
    }
}
