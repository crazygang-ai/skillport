import Foundation
import Yams

// extras is intentionally untyped YAML overflow; Sendable is asserted rather than proven
public struct SKILLMetadata: @unchecked Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var version: String?
    public var allowedTools: [String]?
    public var license: String?
    public var author: String?
    public var extras: [String: Any]

    public init(
        name: String? = nil,
        description: String? = nil,
        version: String? = nil,
        allowedTools: [String]? = nil,
        license: String? = nil,
        author: String? = nil,
        extras: [String: Any] = [:]
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.allowedTools = allowedTools
        self.license = license
        self.author = author
        self.extras = extras
    }

    public static func fromYAML(_ yaml: String) throws -> SKILLMetadata {
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let raw = try Yams.load(yaml: yaml) as? [String: Any]
        else {
            return SKILLMetadata()
        }

        var extras = raw
        let name = extras.removeValue(forKey: "name") as? String
        let description = extras.removeValue(forKey: "description") as? String
        var metadataExtras = extras.removeValue(forKey: "metadata") as? [String: Any] ?? [:]
        let version =
            Self.stringValue(extras.removeValue(forKey: "version"))
            ?? Self.stringValue(metadataExtras.removeValue(forKey: "version"))
        let allowedTools = Self.allowedToolsValue(
            extras.removeValue(forKey: "allowedTools")
                ?? extras.removeValue(forKey: "allowed-tools")
        )
        let license = extras.removeValue(forKey: "license") as? String
        let author =
            Self.stringValue(extras.removeValue(forKey: "author"))
            ?? Self.stringValue(metadataExtras.removeValue(forKey: "author"))
        if !metadataExtras.isEmpty {
            extras["metadata"] = metadataExtras
        }

        return SKILLMetadata(
            name: name,
            description: description,
            version: version,
            allowedTools: allowedTools,
            license: license,
            author: author,
            extras: extras
        )
    }

    public func toYAML() throws -> String {
        var dict: [String: Any] = extras
        if let name {
            dict["name"] = name
        }
        if let description {
            dict["description"] = description
        }
        if let version {
            var metadata = dict.removeValue(forKey: "metadata") as? [String: Any] ?? [:]
            metadata["version"] = version
            dict["metadata"] = metadata
        }
        if let allowedTools {
            dict["allowed-tools"] = allowedTools.joined(separator: ", ")
        }
        if let license {
            dict["license"] = license
        }
        if let author {
            var metadata = dict.removeValue(forKey: "metadata") as? [String: Any] ?? [:]
            metadata["author"] = author
            dict["metadata"] = metadata
        }
        return try Yams.dump(object: dict)
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

    public static func == (lhs: SKILLMetadata, rhs: SKILLMetadata) -> Bool {
        lhs.name == rhs.name
            && lhs.description == rhs.description
            && lhs.version == rhs.version
            && lhs.allowedTools == rhs.allowedTools
            && lhs.license == rhs.license
            && lhs.author == rhs.author
    }
}
