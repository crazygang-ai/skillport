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
            .appendingPathComponent("Scripts/release.sh")
    }
}
