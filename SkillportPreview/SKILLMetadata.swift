import Foundation
import Yams

/// QL extension 用的瘦身版 SKILLMetadata。与主 app 的 `Domain/Types/SKILLMetadata.swift` 保持字段一致。
public struct SKILLMetadata: Sendable, Hashable {
    public let description: String?
    public let version: String?
    public let allowedTools: [String]?

    public init(
        description: String? = nil,
        version: String? = nil,
        allowedTools: [String]? = nil
    ) {
        self.description = description
        self.version = version
        self.allowedTools = allowedTools
    }

    public static func fromYAML(_ yaml: String) throws -> SKILLMetadata {
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SKILLMetadata()
        }
        let node = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return SKILLMetadata(
            description: node["description"] as? String,
            version: node["version"] as? String,
            allowedTools: node["allowedTools"] as? [String]
        )
    }
}
