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
        var node = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        var metadata = node.removeValue(forKey: "metadata") as? [String: Any] ?? [:]
        return SKILLMetadata(
            name: node["name"] as? String,
            description: node["description"] as? String,
            version: stringValue(node["version"]) ?? stringValue(metadata.removeValue(forKey: "version")),
            allowedTools: allowedToolsValue(node["allowedTools"] ?? node["allowed-tools"]),
            license: node["license"] as? String,
            author: stringValue(node["author"]) ?? stringValue(metadata.removeValue(forKey: "author"))
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        return "\(value)"
    }

    private static func allowedToolsValue(_ value: Any?) -> [String]? {
        if let tools = value as? [Any] {
            let parsed = tools.compactMap { stringValue($0) }
            return parsed.isEmpty ? nil : parsed
        }
        guard let raw = stringValue(value) else { return nil }
        let parsed = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return parsed.isEmpty ? nil : parsed
    }
}
