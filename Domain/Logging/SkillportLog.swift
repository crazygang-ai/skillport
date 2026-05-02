import Foundation
import os

/// 集中管理所有 OSLog logger。
/// 使用方式：SkillportLog.scanner.info("scanned \(count) skills")
public enum SkillportLog {
    public static let subsystem = "ai.crazygang.Skillport"

    public static let scanner = Logger(subsystem: subsystem, category: "scanner")
    public static let registry = Logger(subsystem: subsystem, category: "registry")
    public static let installer = Logger(subsystem: subsystem, category: "installer")
    public static let updater = Logger(subsystem: subsystem, category: "updater")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let watcher = Logger(subsystem: subsystem, category: "watcher")
    public static let git = Logger(subsystem: subsystem, category: "git")
    public static let keychain = Logger(subsystem: subsystem, category: "keychain")
    public static let sparkle = Logger(subsystem: subsystem, category: "sparkle")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let manager = Logger(subsystem: subsystem, category: "manager")
}
