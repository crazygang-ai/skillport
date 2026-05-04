import Foundation

public struct ProxyConfig: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case https, socks5 }

    public var enabled: Bool
    public var kind: Kind
    public var host: String
    public var port: Int
    public var username: String?
    /// 不经代理的目标域名列表（支持 `*.internal`、`10.*` 风格 glob）。
    public var bypassList: [String]?

    public init(
        enabled: Bool = false,
        kind: Kind = .https,
        host: String = "",
        port: Int = 0,
        username: String? = nil,
        bypassList: [String]? = nil
    ) {
        self.enabled = enabled
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.bypassList = bypassList
    }

    public static let disabled = ProxyConfig()
}
