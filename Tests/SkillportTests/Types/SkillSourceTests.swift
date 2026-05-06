import Foundation
import Testing

@testable import Skillport

@Suite("SkillSource")
struct SkillSourceTests {
    @Test("GitHub source round-trip with full ref")
    func githubRoundTrip() throws {
        let src = SkillSource.github(owner: "obra", repo: "superpowers", ref: "main")
        let data = try JSONEncoder().encode(src)
        let back = try JSONDecoder().decode(SkillSource.self, from: data)
        #expect(back == src)
    }

    @Test("Local source carries absolute path")
    func localSource() throws {
        let src = SkillSource.local(path: URL(fileURLWithPath: "/tmp/my-skill"))
        let data = try JSONEncoder().encode(src)
        let back = try JSONDecoder().decode(SkillSource.self, from: data)
        #expect(back == src)
    }

    @Test("Registry source carries slug")
    func registrySource() throws {
        let src = SkillSource.registry(slug: "obra/superpowers")
        let data = try JSONEncoder().encode(src)
        let back = try JSONDecoder().decode(SkillSource.self, from: data)
        #expect(back == src)
    }

    @Test("kind property reports stable string tag")
    func kindTag() {
        #expect(SkillSource.github(owner: "a", repo: "b", ref: "m").kind == "github")
        #expect(SkillSource.local(path: URL(fileURLWithPath: "/x")).kind == "local")
        #expect(SkillSource.registry(slug: "x/y").kind == "registry")
    }
}
