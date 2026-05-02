import Foundation
import Testing
@testable import Skillport

@Suite("LockFile")
struct LockFileTests {
    @Test("Decodes v3 sample with github and local sources")
    func decodeV3Sample() throws {
        let url = TestBundleLocator.bundle.url(forResource: "lockfile_v3_sample", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let lock = try LockFile.decode(from: data)
        #expect(lock.version == 3)
        #expect(lock.skills.count == 2)

        let first = lock.skills[0]
        #expect(first.name == "superpowers")
        if case .github(let owner, let repo, let ref) = first.source {
            #expect(owner == "obra")
            #expect(repo == "superpowers")
            #expect(ref == "main")
        } else {
            Issue.record("expected github source")
        }
        #expect(first.commitHash == "abc123def456")

        let second = lock.skills[1]
        if case .local(let path) = second.source {
            #expect(path.path == "/Users/crazy/skills/my-local")
        } else {
            Issue.record("expected local source")
        }
        #expect(second.commitHash == nil)
    }

    @Test("Encode then decode round-trip produces equivalent LockFile")
    func encodeRoundTrip() throws {
        let original = LockFile(
            version: 3,
            skills: [
                LockedSkill(
                    name: "demo",
                    source: .github(owner: "x", repo: "y", ref: "main"),
                    installedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    commitHash: "deadbeef",
                    path: URL(fileURLWithPath: "/tmp/demo")
                )
            ]
        )
        let data = try original.encode()
        let back = try LockFile.decode(from: data)
        #expect(back == original)
    }

    @Test("Version field is always 3; schema upgrades rejected")
    func versionIsFixed() throws {
        let badJSON = #"{"version": 4, "skills": []}"#.data(using: .utf8)!
        #expect(throws: LockFile.DecodingError.unsupportedVersion(4)) {
            _ = try LockFile.decode(from: badJSON)
        }
    }
}
