import Foundation

public enum SkillSource: Codable, Hashable, Sendable {
    case github(owner: String, repo: String, ref: String)
    case local(path: URL)
    case registry(slug: String)

    public var kind: String {
        switch self {
        case .github: return "github"
        case .local: return "local"
        case .registry: return "registry"
        }
    }
}
