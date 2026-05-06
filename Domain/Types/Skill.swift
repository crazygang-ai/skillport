import Foundation

public struct Skill: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: URL
    public let source: SkillSource
    public var frontmatter: SKILLMetadata
    public var installedAgents: Set<AgentID>
    public var updateStatus: UpdateStatus
    public var isManagedBySkillport: Bool

    public var id: SkillIdentity {
        SkillIdentity.compute(name: name, source: source)
    }

    public init(
        name: String,
        path: URL,
        source: SkillSource,
        frontmatter: SKILLMetadata,
        installedAgents: Set<AgentID>,
        updateStatus: UpdateStatus,
        isManagedBySkillport: Bool = false
    ) {
        self.name = name
        self.path = path
        self.source = source
        self.frontmatter = frontmatter
        self.installedAgents = installedAgents
        self.updateStatus = updateStatus
        self.isManagedBySkillport = isManagedBySkillport
    }

    public static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
