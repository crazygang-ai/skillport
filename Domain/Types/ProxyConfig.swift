import Foundation

public struct ProxyConfig: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case https, socks5 }

    public var enabled: Bool
    public var kind: Kind
    public var host: String
    public var port: Int
    public var username: String?

    public init(
        enabled: Bool = false,
        kind: Kind = .https,
        host: String = "",
        port: Int = 0,
        username: String? = nil
    ) {
        self.enabled = enabled
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
    }

    public static let disabled = ProxyConfig()
}
