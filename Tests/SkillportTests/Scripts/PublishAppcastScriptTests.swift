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

    @Test("release script packages a GitHub Release DMG without notarization")
    func releaseScriptPackagesDMGOnly() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)

        #expect(script.contains("Scripts/package-dmg.sh"))
        #expect(!script.contains("Scripts/notarize.sh"))
        #expect(!script.contains("Scripts/publish-appcast.sh"))
        #expect(!script.contains("prepare-export-options.sh"))
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

@Suite("package-dmg.sh")
struct PackageDMGScriptTests {
    @Test("package script creates a compressed DMG from an app bundle")
    func createsCompressedDMG() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)

        #expect(script.contains("hdiutil create"))
        #expect(script.contains("-format UDZO"))
        #expect(script.contains("Skillport-$VERSION.dmg"))
    }

    @Test("package script includes Applications shortcut for install UX")
    func includesApplicationsShortcut() throws {
        let script = try String(contentsOf: scriptURL(), encoding: .utf8)

        #expect(script.contains("ln -s /Applications"))
    }

    private func scriptURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return
            thisFile
            .deletingLastPathComponent()  // Scripts
            .deletingLastPathComponent()  // SkillportTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Scripts/package-dmg.sh")
    }
}

@Suite("release.yml")
struct ReleaseWorkflowTests {
    @Test("release workflow can publish release assets")
    func grantsContentWritePermission() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)

        #expect(workflow.contains("\npermissions:\n  contents: write\n"))
    }

    @Test("release workflow runs full preflight before release build")
    func runsPreflightBeforeReleaseBuild() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)

        let lint = try #require(workflow.range(of: "swift-format lint --recursive"))
        let test = try #require(
            workflow.range(of: "xcodebuild \\\n            -scheme Skillport"))
        let build = try #require(workflow.range(of: "- name: Build release app"))

        #expect(lint.lowerBound < build.lowerBound)
        #expect(test.lowerBound < build.lowerBound)
    }

    @Test("release workflow does not require Apple signing or Sparkle secrets")
    func doesNotRequireSigningOrSparkleSecrets() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)

        #expect(!workflow.contains("DEV_ID_CERT_BASE64"))
        #expect(!workflow.contains("DEVELOPMENT_TEAM"))
        #expect(!workflow.contains("AC_APP_SPECIFIC_PASSWORD"))
        #expect(!workflow.contains("SPARKLE_PRIVATE_KEY_BASE64"))
        #expect(!workflow.contains("notarize.sh"))
        #expect(!workflow.contains("publish-appcast.sh"))
        #expect(!workflow.contains("appcast.xml"))
    }

    @Test("release workflow uploads only GitHub Release DMG")
    func uploadsOnlyGitHubReleaseDMG() throws {
        let workflow = try String(contentsOf: workflowURL(), encoding: .utf8)

        #expect(workflow.contains("./Scripts/package-dmg.sh build/export/Skillport.app"))
        #expect(workflow.contains("build/export/Skillport-*.dmg"))
        #expect(!workflow.contains("build/export/appcast.xml"))
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
