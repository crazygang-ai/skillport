import Foundation

@MainActor
public final class AppContainer {
    public let home: URL
    public let appModel: AppModel
    public let skillsModel: SkillsModel
    public let settingsModel: SettingsModel
    public let updateModel: UpdateModel
    public let notificationModel: NotificationModel
    public let registryModel: RegistryModel
    public let manager: SkillManagerActor
    public let registryActor: RegistryActor
    public let contentFetcher: SkillContentFetcher
    public let repoCache: RepoCacheActor

    public init(home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.home = home
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let cachePath = home.appendingPathComponent(".agents/.skillport-cache.json")
        let cache = CommitHashCache(path: cachePath)
        let git = GitActor()
        let symlinker = SymlinkManagerActor()
        let lockFile = LockFileActor(path: lockPath)
        let repoCache = RepoCacheActor(git: git)
        self.repoCache = repoCache
        let installer = SkillInstallerActor(
            git: git, symlinker: symlinker, lockFile: lockFile, cache: cache, repoCache: repoCache
        )
        let updater = SkillUpdaterActor(
            git: git, cache: cache, repoCache: repoCache, lockFile: lockFile
        )
        let batchChecker = BatchUpdateCheckerActor(updater: updater)
        let watcher = FileWatcherActor()
        let manager = SkillManagerActor(
            scanner: SkillScannerActor(),
            installer: installer,
            updater: updater,
            batchChecker: batchChecker,
            watcher: watcher,
            lockFile: lockFile
        )
        self.manager = manager

        // Registry stack (M5)
        let session = NetworkSession.makeSession(proxy: ProxyConfig())
        let registryActor = RegistryActor(session: session)
        let contentFetcher = SkillContentFetcher(session: session)
        self.registryActor = registryActor
        self.contentFetcher = contentFetcher
        self.registryModel = RegistryModel(
            registry: registryActor,
            contentFetcher: contentFetcher,
            installHandler: { owner, repo, ref, skillId, installTo in
                try await manager.installGitHub(
                    owner: owner, repo: repo, ref: ref,
                    skillId: skillId,
                    home: home, installTo: installTo)
            }
        )

        self.appModel = AppModel()
        self.notificationModel = NotificationModel()
        self.skillsModel = SkillsModel(
            manager: manager, home: home, notifications: self.notificationModel
        )
        self.settingsModel = SettingsModel(proxyActor: ProxySettingsActor())
        self.updateModel = UpdateModel(bridge: AppUpdaterBridge())
    }

    /// Clean up shared `/tmp` repo cache on shutdown.
    public func shutdown() async {
        await repoCache.cleanupAll()
    }
}
