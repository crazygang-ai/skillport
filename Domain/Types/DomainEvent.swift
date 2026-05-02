import Foundation

/// 从 Domain actor 流向 Observable model 的事件。
/// 替代 Electron 版的 EventEmitter + IPC。
public enum DomainEvent: Sendable {
    /// 全量重扫完成
    case skillsReloaded(skills: [Skill])
    /// 单个 skill 的安装状态变化
    case skillInstallationChanged(id: SkillIdentity, agents: Set<AgentID>)
    /// 单个 skill 的更新状态变化
    case skillUpdateStatusChanged(id: SkillIdentity, status: UpdateStatus)
    /// 批量更新检测完成
    case batchUpdateCheckCompleted(available: Int)
    /// 来自 FileWatcher 的原始事件（仅供 SkillManagerActor 订阅后触发重扫，不必一路冒到 UI）
    case fileSystemChanged(paths: [URL])
    /// 通知
    case notification(level: NotificationLevel, message: String)
    /// 错误（供 NotificationModel 展示）
    case error(SkillportError)
}

public enum NotificationLevel: Sendable {
    case info, warning, error, success
}

public enum SkillportError: Error, Sendable, Equatable {
    case fileIO(path: URL, reason: String)
    case gitFailed(exitCode: Int32, stderr: String)
    case keychainFailed(osStatus: Int32)
    case networkFailed(url: URL?, reason: String)
    case parseFailed(file: URL?, reason: String)
    case invalidLockFile(reason: String)
    case unexpected(String)
}
