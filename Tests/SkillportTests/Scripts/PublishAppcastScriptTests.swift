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

    private func scriptURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return
            thisFile
            .deletingLastPathComponent()  // Scripts
            .deletingLastPathComponent()  // SkillportTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Scripts/publish-appcast.sh")
    }
}
