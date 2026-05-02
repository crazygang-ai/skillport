import Foundation
import Testing

@testable import Skillport

@Suite("NetworkSession")
struct NetworkSessionTests {
    @Test("Returns URLSession with proxy config applied when enabled")
    func appliesProxy() {
        let cfg = ProxyConfig(enabled: true, kind: .https, host: "proxy.test", port: 8080)
        let session = NetworkSession.makeSession(proxy: cfg)
        let proxies = session.configuration.connectionProxyDictionary ?? [:]
        #expect(proxies[kCFNetworkProxiesHTTPSEnable] as? NSNumber == 1)
        #expect(proxies[kCFNetworkProxiesHTTPSProxy] as? String == "proxy.test")
        #expect(proxies[kCFNetworkProxiesHTTPSPort] as? NSNumber == 8080)
    }

    @Test("Returns plain session when proxy disabled")
    func noProxyWhenDisabled() {
        let session = NetworkSession.makeSession(proxy: .disabled)
        #expect((session.configuration.connectionProxyDictionary ?? [:]).isEmpty)
    }

    @Test("SOCKS5 sets corresponding CFNetwork keys")
    func socks5() {
        let cfg = ProxyConfig(enabled: true, kind: .socks5, host: "127.0.0.1", port: 1080)
        let session = NetworkSession.makeSession(proxy: cfg)
        let proxies = session.configuration.connectionProxyDictionary ?? [:]
        #expect(proxies[kCFStreamPropertySOCKSProxyHost] as? String == "127.0.0.1")
        #expect(proxies[kCFStreamPropertySOCKSProxyPort] as? NSNumber == 1080)
    }
}
