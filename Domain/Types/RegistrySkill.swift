import Foundation

public struct RegistrySkill: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let skillId: String
    public let name: String
    public let installs: Int
    public let source: String
    public let installsYesterday: Int?
    public let change: Int?

    public init(
        id: String,
        skillId: String,
        name: String,
        installs: Int,
        source: String,
        installsYesterday: Int? = nil,
        change: Int? = nil
    ) {
        self.id = id
        self.skillId = skillId
        self.name = name
        self.installs = installs
        self.source = source
        self.installsYesterday = installsYesterday
        self.change = change
    }

    public var installCommand: String {
        "npx skills add https://github.com/\(source) --skill \(skillId)"
    }

    public var isSingleSkillRepo: Bool {
        let parts = source.split(separator: "/")
        guard parts.count == 2 else { return false }
        return String(parts[1]) == skillId
    }

    public var ownerAndRepo: (owner: String, repo: String)? {
        let parts = source.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

public enum LeaderboardCategory: String, CaseIterable, Sendable, Hashable, Codable {
    case allTime
    case trending
    case hot

    public var urlPath: String {
        switch self {
        case .allTime: return ""
        case .trending: return "/trending"
        case .hot: return "/hot"
        }
    }
}

public struct LeaderboardResult: Sendable, Hashable {
    public let skills: [RegistrySkill]
    public let totalCount: Int

    public init(skills: [RegistrySkill] = [], totalCount: Int = 0) {
        self.skills = skills
        self.totalCount = totalCount
    }
}
