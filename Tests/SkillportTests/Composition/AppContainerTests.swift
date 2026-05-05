import Foundation
import Testing

@testable import Skillport

@Suite("AppContainer")
@MainActor
struct AppContainerTests {
    @Test("Creates all models and actors without throwing")
    func createsGraph() {
        let dir = try! TempDir.create()
        defer { try? dir.cleanup() }
        let container = AppContainer(home: dir.url)
        #expect(container.home == dir.url)
        #expect(container.skillsModel.agents.count == AgentID.allCases.count)
    }

    @Test("Settings proxy source is shared by registry, content fetcher, and git")
    func sharedProxySource() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let suite = "skillport-container-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let proxySettings = ProxySettingsActor(suiteName: suite)
        let container = AppContainer(
            home: dir.url,
            proxySettings: proxySettings,
            keychain: KeychainActor(service: "skillport-test-\(UUID())"),
            defaults: defaults,
            repoCacheRoot: dir.url.appendingPathComponent("repo-cache")
        )
        let proxy = ProxyConfig(
            enabled: true,
            kind: .https,
            host: "proxy.local",
            port: 8080,
            username: "alice",
            bypassList: ["localhost", "*.internal"]
        )

        await container.settingsModel.apply(proxy: proxy)

        let registryProxy = await container.registryActor.currentConnectionProxySummary()
        let fetcherProxy = await container.contentFetcher.currentConnectionProxySummary()
        #expect(registryProxy["HTTPSProxy"] == "proxy.local")
        #expect(fetcherProxy["HTTPSPort"] == "8080")

        let gitEnv = await container.git.effectiveProxyEnvironmentForTesting(password: "secret")
        #expect(gitEnv["HTTPS_PROXY"] == "http://alice:secret@proxy.local:8080")
        #expect(gitEnv["NO_PROXY"] == "localhost,*.internal")

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("shutdown stops watching and cleans repo cache root")
    func shutdownStopsWatchingAndCleansCache() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let repoCacheRoot = dir.url.appendingPathComponent("repo-cache")
        try FileManager.default.createDirectory(at: repoCacheRoot, withIntermediateDirectories: true)
        let container = AppContainer(home: dir.url, repoCacheRoot: repoCacheRoot)

        await container.skillsModel.startWatching()
        #expect(await container.manager.isWatching == true)
        await container.shutdown()

        #expect(await container.manager.isWatching == false)
        #expect(!FileManager.default.fileExists(atPath: repoCacheRoot.path))
    }
}
