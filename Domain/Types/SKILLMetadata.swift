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
        let version: String?
        if let v = extras.removeValue(forKey: "version") {
            version = "\(v)"
        } else {
            version = nil
        }
        let allowedTools: [String]?
        if let tools = extras.removeValue(forKey: "allowedTools") as? [Any] {
            allowedTools = tools.compactMap { $0 as? String }
        } else {
            allowedTools = nil
        }
        let license = extras.removeValue(forKey: "license") as? String
        let author = extras.removeValue(forKey: "author") as? String

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
            dict["version"] = version
        }
        if let allowedTools {
            dict["allowedTools"] = allowedTools
        }
        if let license {
            dict["license"] = license
        }
        if let author {
            dict["author"] = author
        }
        return try Yams.dump(object: dict)
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
