import Foundation
import Testing

@testable import Skillport

@Suite("BatchUpdateCheckerActor")
struct BatchUpdateCheckerActorTests {
    @Test("Runs checkStatus for each skill with bounded concurrency")
    func runsAll() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let cache = CommitHashCache(path: dir.url.appendingPathComponent("c.json"))
        let updater = SkillUpdaterActor(git: GitActor(), cache: cache)
        let checker = BatchUpdateCheckerActor(updater: updater, maxConcurrent: 2)

        let skills: [Skill] = (1...5).map {
            Skill(
                name: "s\($0)",
                path: dir.url.appendingPathComponent("s\($0)"),
                source: .local(path: dir.url.appendingPathComponent("s\($0)")),
                frontmatter: SKILLMetadata(),
                installedAgents: [],
                updateStatus: .unknown
            )
        }
        let results = try await checker.checkAll(skills: skills)
        #expect(results.count == 5)
        #expect(results.values.allSatisfy { $0 == .upToDate })  // 全是 local
    }
}
