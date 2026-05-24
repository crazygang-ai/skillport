import Testing

@testable import Skillport

@Suite("GitHubRepoReference")
struct GitHubRepoReferenceTests {
    @Test("parses owner slash repo shorthand")
    func parsesShorthand() throws {
        let ref = try GitHubRepoReference.parse("crazygang-ai/skillport")

        #expect(ref.owner == "crazygang-ai")
        #expect(ref.repo == "skillport")
        #expect(ref.gitURL.absoluteString == "https://github.com/crazygang-ai/skillport.git")
    }

    @Test("parses GitHub URL with optional dot-git suffix")
    func parsesURL() throws {
        let ref = try GitHubRepoReference.parse("https://github.com/owner/repo.git")

        #expect(ref.owner == "owner")
        #expect(ref.repo == "repo")
        #expect(ref.gitURL.absoluteString == "https://github.com/owner/repo.git")
    }

    @Test("rejects non-GitHub URLs")
    func rejectsNonGitHubURL() {
        #expect(throws: SkillportError.self) {
            _ = try GitHubRepoReference.parse("https://example.com/owner/repo")
        }
    }
}
