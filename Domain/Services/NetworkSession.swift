import Foundation

public enum NetworkSession {
    /// 根据 ProxyConfig 构造一个 URLSession。
    /// 调用方负责持有 session。
    public static func makeSession(proxy: ProxyConfig) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60

        if proxy.enabled, !proxy.host.isEmpty, proxy.port > 0 {
            var dict: [AnyHashable: Any] = [:]
            switch proxy.kind {
            case .https:
                dict[kCFNetworkProxiesHTTPSEnable] = 1 as NSNumber
                dict[kCFNetworkProxiesHTTPSProxy] = proxy.host
                dict[kCFNetworkProxiesHTTPSPort] = proxy.port as NSNumber
            case .socks5:
                dict[kCFStreamPropertySOCKSProxyHost] = proxy.host
                dict[kCFStreamPropertySOCKSProxyPort] = proxy.port as NSNumber
                dict[kCFStreamPropertySOCKSVersion] = kCFStreamSocketSOCKSVersion5
            }
            config.connectionProxyDictionary = dict
        }
        return URLSession(configuration: config)
    }
}
