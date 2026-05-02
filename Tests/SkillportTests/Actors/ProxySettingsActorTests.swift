import Foundation
import Testing

@testable import Skillport

@Suite("ProxySettingsActor")
struct ProxySettingsActorTests {
    @Test("Default is disabled config")
    func defaultConfig() async throws {
        let suiteName = "skillport-test-\(UUID().uuidString)"
        let actor = ProxySettingsActor(suiteName: suiteName)
        let cfg = await actor.current
        #expect(cfg.enabled == false)
        #expect(cfg.kind == .https)
        #expect(cfg.host == "")
        #expect(cfg.port == 0)
        #expect(cfg.username == nil)
    }

    @Test("Save then read round-trip through UserDefaults")
    func saveAndRead() async throws {
        let suiteName = "skillport-test-\(UUID().uuidString)"
        let actor = ProxySettingsActor(suiteName: suiteName)
        let new = ProxyConfig(
            enabled: true,
            kind: .socks5,
            host: "127.0.0.1",
            port: 1080,
            username: "alice"
        )
        await actor.save(new)
        let back = await actor.current
        #expect(back == new)

        // 重建 actor 确认持久化
        let reloaded = ProxySettingsActor(suiteName: suiteName)
        #expect(await reloaded.current == new)
    }
}
