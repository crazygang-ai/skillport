import Foundation

public enum NetworkSession {
    /// 根据 ProxyConfig 构造一个 URLSession。
    /// 调用方负责持有 session。
    public static func makeSession(proxy: ProxyConfig, password: String? = nil) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60

        let dict = connectionProxyDictionary(proxy: proxy, password: password)
        if !dict.isEmpty {
            config.connectionProxyDictionary = dict
        }
        return URLSession(configuration: config)
    }

    public static func connectionProxyDictionary(
        proxy: ProxyConfig,
        password: String? = nil
    ) -> [AnyHashable: Any] {
        guard proxy.enabled, !proxy.host.isEmpty, proxy.port > 0 else {
            return [:]
        }
        var dict: [AnyHashable: Any] = [:]
        switch proxy.kind {
        case .https:
            dict[kCFNetworkProxiesHTTPEnable] = 1 as NSNumber
            dict[kCFNetworkProxiesHTTPProxy] = proxy.host
            dict[kCFNetworkProxiesHTTPPort] = proxy.port as NSNumber
            dict[kCFNetworkProxiesHTTPSEnable] = 1 as NSNumber
            dict[kCFNetworkProxiesHTTPSProxy] = proxy.host
            dict[kCFNetworkProxiesHTTPSPort] = proxy.port as NSNumber
        case .socks5:
            dict[kCFNetworkProxiesSOCKSEnable] = 1 as NSNumber
            dict[kCFNetworkProxiesSOCKSProxy] = proxy.host
            dict[kCFNetworkProxiesSOCKSPort] = proxy.port as NSNumber
            // Keep the older stream keys too; URLSession has historically honored
            // both dictionaries depending on OS release.
            dict[kCFStreamPropertySOCKSProxyHost] = proxy.host
            dict[kCFStreamPropertySOCKSProxyPort] = proxy.port as NSNumber
            dict[kCFStreamPropertySOCKSVersion] = kCFStreamSocketSOCKSVersion5
        }
        if let bypass = proxy.bypassList, !bypass.isEmpty {
            dict[kCFNetworkProxiesExceptionsList] = bypass
        }
        if let username = proxy.username, !username.isEmpty {
            dict[kCFProxyUsernameKey] = username
            if let password, !password.isEmpty {
                dict[kCFProxyPasswordKey] = password
            }
        }
        return dict
    }

    public static func proxyEnvironment(
        proxy: ProxyConfig,
        password: String? = nil
    ) -> [String: String] {
        guard let proxyURL = proxyURLString(proxy: proxy, password: password) else {
            return [:]
        }
        var env = [
            "HTTP_PROXY": proxyURL,
            "HTTPS_PROXY": proxyURL,
            "ALL_PROXY": proxyURL,
            "http_proxy": proxyURL,
            "https_proxy": proxyURL,
            "all_proxy": proxyURL,
        ]
        if let bypass = proxy.bypassList, !bypass.isEmpty {
            let noProxy = bypass.joined(separator: ",")
            env["NO_PROXY"] = noProxy
            env["no_proxy"] = noProxy
        }
        return env
    }

    public static func connectionProxySummary(
        proxy: ProxyConfig,
        password: String? = nil
    ) -> [String: String] {
        connectionProxySummary(from: connectionProxyDictionary(proxy: proxy, password: password))
    }

    public static func connectionProxySummary(from dict: [AnyHashable: Any]) -> [String: String] {
        var summary: [String: String] = [:]
        if let host = dict[kCFNetworkProxiesHTTPSProxy] as? String {
            summary["HTTPSProxy"] = host
        }
        if let port = dict[kCFNetworkProxiesHTTPSPort] as? NSNumber {
            summary["HTTPSPort"] = port.stringValue
        }
        if let host = dict[kCFNetworkProxiesSOCKSProxy] as? String {
            summary["SOCKSProxy"] = host
        }
        if let port = dict[kCFNetworkProxiesSOCKSPort] as? NSNumber {
            summary["SOCKSPort"] = port.stringValue
        }
        if let bypass = dict[kCFNetworkProxiesExceptionsList] as? [String] {
            summary["ExceptionsList"] = bypass.joined(separator: ",")
        }
        return summary
    }

    private static func proxyURLString(proxy: ProxyConfig, password: String?) -> String? {
        guard proxy.enabled, !proxy.host.isEmpty, proxy.port > 0 else {
            return nil
        }
        var components = URLComponents()
        components.scheme = proxy.kind == .socks5 ? "socks5" : "http"
        components.host = proxy.host
        components.port = proxy.port
        if let username = proxy.username, !username.isEmpty {
            components.user = username
            if let password, !password.isEmpty {
                components.password = password
            }
        }
        return components.string
    }
}
