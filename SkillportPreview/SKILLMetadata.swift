import Foundation
import Yams

/// QL extension 用的瘦身版 SKILLMetadata。与主 app 的 `Domain/Types/SKILLMetadata.swift` 保持字段一致。
public struct SKILLMetadata: Sendable, Hashable {
    public var name: String?
    public var description: String?
    public var version: String?
    public var allowedTools: [String]?
    public var license: String?
    public var author: String?

    public init(
        name: String? = nil,
        description: String? = nil,
        version: String? = nil,
        allowedTools: [String]? = nil,
        license: String? = nil,
        author: String? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.allowedTools = allowedTools
        self.license = license
        self.author = author
    }

    public static func fromYAML(_ yaml: String) throws -> SKILLMetadata {
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SKILLMetadata()
        }
        let node = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return SKILLMetadata(
            name: node["name"] as? String,
            description: node["description"] as? String,
            version: node["version"] as? String,
            allowedTools: node["allowedTools"] as? [String],
            license: node["license"] as? String,
            author: node["author"] as? String
        )
    }
}
