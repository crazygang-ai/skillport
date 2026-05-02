import Foundation
import Testing

@testable import Skillport

@Suite("Skill")
struct SkillTests {
    @Test("Skill exposes id computed from identity")
    func idFromIdentity() {
        let skill = Skill(
            name: "superpowers",
            path: URL(fileURLWithPath: "/Users/me/.agents/skills/superpowers"),
            source: .github(owner: "obra", repo: "superpowers", ref: "main"),
            frontmatter: SKILLMetadata(description: "a skill"),
            installedAgents: [.claudeCode, .cursor],
            updateStatus: .upToDate
        )
        #expect(
            skill.id
                == SkillIdentity.compute(
                    name: "superpowers",
                    source: .github(owner: "obra", repo: "superpowers", ref: "main")
                ))
    }

    @Test("Skill is Hashable and Equatable by id only")
    func hashableByID() {
        let base = Skill(
            name: "x",
            path: URL(fileURLWithPath: "/p/x"),
            source: .registry(slug: "a/x"),
            frontmatter: SKILLMetadata(),
            installedAgents: [],
            updateStatus: .unknown
        )
        let sameIdentity = Skill(
            name: "x",
            path: URL(fileURLWithPath: "/other/path"),  // 路径变了，但 identity 相同
            source: .registry(slug: "a/x"),
            frontmatter: SKILLMetadata(description: "diff"),
            installedAgents: [.codex],
            updateStatus: .available(remoteHash: "h")
        )
        #expect(base == sameIdentity)
        #expect(base.hashValue == sameIdentity.hashValue)
    }
}
