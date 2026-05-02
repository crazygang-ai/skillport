import Foundation

@MainActor
public final class AppContainer {
    public let home: URL
    public let appModel: AppModel
    public let skillsModel: SkillsModel
    public let settingsModel: SettingsModel
    public let updateModel: UpdateModel
    public let notificationModel: NotificationModel
    public let manager: SkillManagerActor

    public init(home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.home = home
        let lockPath = home.appendingPathComponent(".agents/.skill-lock.json")
        let cachePath = home.appendingPathComponent(".agents/.skillpilot-cache.json")
        let cache = CommitHashCache(path: cachePath)
        let git = GitActor()
        let symlinker = SymlinkManagerActor()
        let lockFile = LockFileActor(path: lockPath)
        let installer = SkillInstallerActor(
            git: git, symlinker: symlinker, lockFile: lockFile, cache: cache
        )
        let updater = SkillUpdaterActor(git: git, cache: cache)
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

        self.appModel = AppModel()
        self.skillsModel = SkillsModel(manager: manager, home: home)
        self.notificationModel = NotificationModel()
        self.settingsModel = SettingsModel(proxyActor: ProxySettingsActor())
        self.updateModel = UpdateModel(bridge: AppUpdaterBridge(feedURL: nil))
    }
}
