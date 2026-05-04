import Foundation

// MARK: - Public types

public struct LockFile: Equatable, Sendable {
    public static let currentVersion: Int = 3
    public let version: Int
    public var skills: [LockedSkill]

    public init(version: Int = LockFile.currentVersion, skills: [LockedSkill]) {
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
    /// subdir tree hash (git rev-parse HEAD:<skillPath>) — baseline for update detection.
    public let skillFolderHash: String?
    /// 相对 repo 根的子目录路径；单 skill 仓库时为 nil 或 ""。
    public let skillPath: String?
    /// 最近一次更新落地的时间。
    public let updatedAt: Date?
    /// 用户 dismiss 的 remote tree hash；相等时 checkStatus 返回 upToDate。
    public let dismissedUpdate: String?
    /// 用户上次在安装对话框选中的 agent 集合；用于恢复 UX 状态。
    public let lastSelectedAgents: Set<AgentID>?

    public init(
        name: String,
        source: SkillSource,
        installedAt: Date,
        commitHash: String?,
        path: URL,
        skillFolderHash: String? = nil,
        skillPath: String? = nil,
        updatedAt: Date? = nil,
        dismissedUpdate: String? = nil,
        lastSelectedAgents: Set<AgentID>? = nil
    ) {
        self.name = name
        self.source = source
        self.installedAt = installedAt
        self.commitHash = commitHash
        self.path = path
        self.skillFolderHash = skillFolderHash
        self.skillPath = skillPath
        self.updatedAt = updatedAt
        self.dismissedUpdate = dismissedUpdate
        self.lastSelectedAgents = lastSelectedAgents
    }

    fileprivate init(wire: WireLockedSkill) throws {
        self.name = wire.name
        self.source = try SkillSource(wireSource: wire.source)
        self.installedAt = wire.installedAt
        self.commitHash = wire.commitHash
        self.path = URL(fileURLWithPath: wire.path)
        self.skillFolderHash = wire.skillFolderHash
        self.skillPath = wire.skillPath
        self.updatedAt = wire.updatedAt
        self.dismissedUpdate = wire.dismissedUpdate
        self.lastSelectedAgents = wire.lastSelectedAgents.map { Set($0) }
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
    let skillFolderHash: String?
    let skillPath: String?
    let updatedAt: Date?
    let dismissedUpdate: String?
    let lastSelectedAgents: [AgentID]?

    init(skill: LockedSkill) {
        self.name = skill.name
        self.source = WireSource(source: skill.source)
        self.installedAt = skill.installedAt
        self.commitHash = skill.commitHash
        self.path = skill.path.path
        self.skillFolderHash = skill.skillFolderHash
        self.skillPath = skill.skillPath
        self.updatedAt = skill.updatedAt
        self.dismissedUpdate = skill.dismissedUpdate
        self.lastSelectedAgents = skill.lastSelectedAgents.map { Array($0).sorted { $0.rawValue < $1.rawValue } }
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
