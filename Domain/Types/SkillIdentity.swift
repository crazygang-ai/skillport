import Foundation

/// Stable identity for a skill: encodes source + name so two installs of the same
/// upstream skill (different names) are distinguishable, and two installs from
/// different sources with the same name don't collide.
public struct SkillIdentity: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func compute(name: String, source: SkillSource) -> SkillIdentity {
        switch source {
        case .github(let owner, let repo, let ref):
            return SkillIdentity(rawValue: "github:\(owner)/\(repo)@\(ref)#\(name)")
        case .local(let path):
            return SkillIdentity(rawValue: "local:\(path.path)#\(name)")
        case .registry(let slug):
            return SkillIdentity(rawValue: "registry:\(slug)#\(name)")
        }
    }
}

extension SkillIdentity: CustomStringConvertible {
    public var description: String { rawValue }
}
