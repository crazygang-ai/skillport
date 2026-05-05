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

    @Test("Slow checks do not block dispatching later queued skills")
    func slowCheckDoesNotBlockLaterDispatch() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let probe = DispatchProbe()
        let checker = BatchUpdateCheckerActor(maxConcurrent: 2) { skill in
            await probe.markStarted(skill.name)
            if skill.name == "s1" {
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            return .upToDate
        }
        let skills: [Skill] = (1...3).map {
            Skill(
                name: "s\($0)",
                path: dir.url.appendingPathComponent("s\($0)"),
                source: .local(path: dir.url.appendingPathComponent("s\($0)")),
                frontmatter: SKILLMetadata(),
                installedAgents: [],
                updateStatus: .unknown
            )
        }

        async let results = checker.checkAll(skills: skills)
        try await Task.sleep(nanoseconds: 150_000_000)
        let started = await probe.startedNames()
        #expect(started.contains("s3"))
        let finalResults = try await results
        #expect(finalResults.count == 3)
    }
}

private actor DispatchProbe {
    private var names: [String] = []

    func markStarted(_ name: String) {
        names.append(name)
    }

    func startedNames() -> [String] {
        names
    }
}
