import Foundation
import Testing

@testable import Skillport

@Suite("RegistrySkill value type")
struct RegistrySkillTests {
    @Test("LeaderboardCategory has three cases matching skills.sh URL paths")
    func leaderboardCategoryCases() {
        #expect(LeaderboardCategory.allTime.urlPath == "")
        #expect(LeaderboardCategory.trending.urlPath == "/trending")
        #expect(LeaderboardCategory.hot.urlPath == "/hot")
        #expect(LeaderboardCategory.allCases.count == 3)
    }

    @Test("RegistrySkill Codable roundtrip preserves all fields")
    func roundtrip() throws {
        let input = RegistrySkill(
            id: "owner/repo/skill-id",
            skillId: "skill-id",
            name: "Skill Name",
            installs: 1234,
            source: "owner/repo",
            installsYesterday: 10,
            change: 5
        )
        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(RegistrySkill.self, from: data)
        #expect(decoded == input)
    }

    @Test("installCommand returns correct npx skills add string")
    func installCommandFormat() {
        let s = RegistrySkill(id: "a/b/c", skillId: "c", name: "c", installs: 0, source: "a/b")
        #expect(s.installCommand == "npx skills add https://github.com/a/b --skill c")
    }

    @Test("isSingleSkillRepo true when skillId matches repo segment of source")
    func singleSkillRepoDetection() {
        let single = RegistrySkill(id: "a/b/b", skillId: "b", name: "b", installs: 0, source: "a/b")
        #expect(single.isSingleSkillRepo == true)

        let multi = RegistrySkill(id: "a/b/c", skillId: "c", name: "c", installs: 0, source: "a/b")
        #expect(multi.isSingleSkillRepo == false)

        let malformed = RegistrySkill(id: "x", skillId: "x", name: "x", installs: 0, source: "onlyone")
        #expect(malformed.isSingleSkillRepo == false)
    }

    @Test("ownerAndRepo parses source into tuple or nil")
    func ownerAndRepoParse() {
        let s = RegistrySkill(id: "a/b/c", skillId: "c", name: "c", installs: 0, source: "a/b")
        let parts = s.ownerAndRepo
        #expect(parts?.owner == "a")
        #expect(parts?.repo == "b")

        let bad = RegistrySkill(id: "x", skillId: "x", name: "x", installs: 0, source: "bad")
        #expect(bad.ownerAndRepo == nil)
    }

    @Test("LeaderboardResult default is empty")
    func leaderboardResultEmpty() {
        let r = LeaderboardResult()
        #expect(r.skills.isEmpty)
        #expect(r.totalCount == 0)
    }
}
