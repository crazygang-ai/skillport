import Foundation
import Testing
@testable import Skillport

@Suite("SkillIdentity")
struct SkillIdentityTests {
    @Test("GitHub skill identity is stable: owner/repo@ref#name")
    func githubIdentity() {
        let id = SkillIdentity.compute(
            name: "superpowers",
            source: .github(owner: "obra", repo: "superpowers", ref: "main")
        )
        #expect(id.rawValue == "github:obra/superpowers@main#superpowers")
    }

    @Test("Local skill identity uses absolute path + name")
    func localIdentity() {
        let id = SkillIdentity.compute(
            name: "my-skill",
            source: .local(path: URL(fileURLWithPath: "/Users/me/skills/my-skill"))
        )
        #expect(id.rawValue == "local:/Users/me/skills/my-skill#my-skill")
    }

    @Test("Registry skill identity uses slug + name")
    func registryIdentity() {
        let id = SkillIdentity.compute(
            name: "core",
            source: .registry(slug: "official/core")
        )
        #expect(id.rawValue == "registry:official/core#core")
    }

    @Test("Identity is Codable and Hashable (usable as dict key)")
    func codableAndHashable() throws {
        let id1 = SkillIdentity.compute(
            name: "x",
            source: .github(owner: "a", repo: "b", ref: "main")
        )
        let id2 = SkillIdentity.compute(
            name: "x",
            source: .github(owner: "a", repo: "b", ref: "main")
        )
        #expect(id1 == id2)
        #expect(id1.hashValue == id2.hashValue)

        let data = try JSONEncoder().encode(id1)
        let back = try JSONDecoder().decode(SkillIdentity.self, from: data)
        #expect(back == id1)
    }
}
