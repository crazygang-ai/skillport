import Foundation
import Testing

@Suite("publish-appcast.sh")
struct PublishAppcastScriptTests {
    @Test("default appcast URL is based on APPCAST_DMG_BASE_URL, not the DMG file URL")
    func defaultAppcastURL() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)

        #expect(!script.contains("$DMG_URL/../appcast.xml"))
        #expect(script.contains(#"APPCAST_FEED_URL="${APPCAST_URL:-$BASE_URL/appcast.xml}""#))
    }

    @Test("sign_update is asked for signature-only output")
    func signatureOnlyOutput() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)

        #expect(script.contains(#""$SIGN_TOOL" -p -f "$KEY_PATH" "$DMG_PATH""#))
    }

    @Test("appcast separates build version from marketing version")
    func appcastUsesBuildVersion() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)
        let template = try String(contentsOf: appcastTemplateURL(), encoding: .utf8)

        #expect(script.contains("BUILD_VERSION="))
        #expect(script.contains("{{BUILD_VERSION}}"))
        #expect(template.contains(#"sparkle:version="{{BUILD_VERSION}}""#))
        #expect(template.contains(#"sparkle:shortVersionString="{{VERSION}}""#))
    }

    private func scriptURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return
            thisFile
            .deletingLastPathComponent()  // Scripts
            .deletingLastPathComponent()  // SkillportTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Scripts/publish-appcast.sh")
    }

    private func appcastTemplateURL() -> URL {
        scriptURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/appcast.template.xml")
    }
}

@Suite("release.sh")
struct ReleaseScriptTests {
    @Test("release script can run tests without xcpretty installed")
    func xcprettyIsOptional() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)

        #expect(script.contains("command -v xcpretty"))
        #expect(!script.contains("test | xcpretty ||"))
    }

    private func scriptURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return
            thisFile
            .deletingLastPathComponent()  // Scripts
            .deletingLastPathComponent()  // SkillportTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Scripts/release.sh")
    }
}

@Suite("release.yml")
struct ReleaseWorkflowTests {
    @Test("release workflow can publish release assets")
    func grantsContentWritePermission() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)

        #expect(workflow.contains("\npermissions:\n  contents: write\n"))
    }

    @Test("release workflow runs full preflight before archive")
    func runsPreflightBeforeArchive() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)

        let lint = try #require(workflow.range(of: "swift-format lint --recursive"))
        let test = try #require(
            workflow.range(of: "xcodebuild \\\n            -scheme Skillport"))
        let archive = try #require(workflow.range(of: "- name: Archive"))

        #expect(lint.lowerBound < archive.lowerBound)
        #expect(test.lowerBound < archive.lowerBound)
    }

    @Test("release workflow derives appcast URLs from the release tag")
    func derivesAppcastURLsFromTag() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)
        let expectedDMGBaseURL =
            "APPCAST_DMG_BASE_URL: "
            + "https://github.com/crazygang-ai/skillport/releases/download/"
            + "${{ github.ref_name }}"
        let expectedAppcastURL =
            "APPCAST_URL: "
            + "https://github.com/crazygang-ai/skillport/releases/latest/download/appcast.xml"

        #expect(!workflow.contains("secrets.APPCAST_DMG_BASE_URL"))
        #expect(workflow.contains(expectedDMGBaseURL))
        #expect(workflow.contains(expectedAppcastURL))
    }

    private func workflowURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return
            thisFile
            .deletingLastPathComponent()  // Scripts
            .deletingLastPathComponent()  // SkillportTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent(".github/workflows/release.yml")
    }
}
