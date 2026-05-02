import Foundation

// MARK: - Public types

public struct LockFile: Equatable, Sendable {
    public let version: Int
    public let skills: [LockedSkill]

    public init(version: Int, skills: [LockedSkill]) {
        self.version = version
        self.skills = skills
    }

    public enum DecodingError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    public static func decode(from data: Data) throws -> LockFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire = try decoder.decode(WireLockFile.self, from: data)
        guard wire.version == 3 else {
            throw DecodingError.unsupportedVersion(wire.version)
        }
        let skills = try wire.skills.map { try LockedSkill(wire: $0) }
        return LockFile(version: wire.version, skills: skills)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let wire = WireLockFile(
            version: version,
            skills: skills.map { WireLockedSkill(skill: $0) }
        )
        return try encoder.encode(wire)
    }
}

public struct LockedSkill: Equatable, Sendable {
    public let name: String
    public let source: SkillSource
    public let installedAt: Date
    public let commitHash: String?
    public let path: URL

    public init(
        name: String,
        source: SkillSource,
        installedAt: Date,
        commitHash: String?,
        path: URL
    ) {
        self.name = name
        self.source = source
        self.installedAt = installedAt
        self.commitHash = commitHash
        self.path = path
    }

    fileprivate init(wire: WireLockedSkill) throws {
        self.name = wire.name
        self.source = try SkillSource(wireSource: wire.source)
        self.installedAt = wire.installedAt
        self.commitHash = wire.commitHash
        self.path = URL(fileURLWithPath: wire.path)
    }
}

// MARK: - Wire types (private serialization layer)

private struct WireLockFile: Codable {
    let version: Int
    let skills: [WireLockedSkill]
}

private struct WireLockedSkill: Codable {
    let name: String
    let source: WireSource
    let installedAt: Date
    let commitHash: String?
    let path: String

    init(skill: LockedSkill) {
        self.name = skill.name
        self.source = WireSource(source: skill.source)
        self.installedAt = skill.installedAt
        self.commitHash = skill.commitHash
        self.path = skill.path.path
    }
}

private struct WireSource: Codable {
    let type: String
    // github fields
    let owner: String?
    let repo: String?
    let ref: String?
    // local fields
    let path: String?
    // registry fields
    let slug: String?

    init(source: SkillSource) {
        switch source {
        case .github(let owner, let repo, let ref):
            self.type = "github"
            self.owner = owner
            self.repo = repo
            self.ref = ref
            self.path = nil
            self.slug = nil
        case .local(let url):
            self.type = "local"
            self.owner = nil
            self.repo = nil
            self.ref = nil
            self.path = url.path
            self.slug = nil
        case .registry(let slug):
            self.type = "registry"
            self.owner = nil
            self.repo = nil
            self.ref = nil
            self.path = nil
            self.slug = slug
        }
    }
}

private enum SourceParseError: Error {
    case missingField(String)
    case unknownType(String)
}

private extension SkillSource {
    init(wireSource: WireSource) throws {
        switch wireSource.type {
        case "github":
            guard let owner = wireSource.owner,
                let repo = wireSource.repo,
                let ref = wireSource.ref
            else {
                throw SourceParseError.missingField("github requires owner, repo, ref")
            }
            self = .github(owner: owner, repo: repo, ref: ref)
        case "local":
            guard let path = wireSource.path else {
                throw SourceParseError.missingField("local requires path")
            }
            self = .local(path: URL(fileURLWithPath: path))
        case "registry":
            guard let slug = wireSource.slug else {
                throw SourceParseError.missingField("registry requires slug")
            }
            self = .registry(slug: slug)
        default:
            throw SourceParseError.unknownType(wireSource.type)
        }
    }
}
