import Foundation

public actor SymlinkManagerActor {
    public init() {}

    public func link(target: URL, at linkURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: linkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let existing = try? fm.destinationOfSymbolicLink(atPath: linkURL.path) {
            let existingURL =
                existing.hasPrefix("/")
                ? URL(fileURLWithPath: existing)
                : linkURL.deletingLastPathComponent().appendingPathComponent(existing)
            if existingURL.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path {
                return
            }
            throw SkillportError.fileIO(
                path: linkURL,
                reason: "path exists as a symlink to another target"
            )
        }
        if fm.fileExists(atPath: linkURL.path) {
            throw SkillportError.fileIO(path: linkURL, reason: "path exists and is not a symlink")
        }
        try fm.createSymbolicLink(at: linkURL, withDestinationURL: target)
    }

    public func unlink(at linkURL: URL, expectedTarget: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: linkURL.path) else { return }
        guard let actual = try? fm.destinationOfSymbolicLink(atPath: linkURL.path) else {
            throw SkillportError.fileIO(path: linkURL, reason: "not a symlink; refuse to remove")
        }
        guard actual == expectedTarget.path else {
            throw SkillportError.fileIO(
                path: linkURL,
                reason: "symlink points at \(actual), expected \(expectedTarget.path)"
            )
        }
        try fm.removeItem(at: linkURL)
    }

    public func isLinked(target: URL, at linkURL: URL) -> Bool {
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
        else {
            return false
        }
        return resolved == target.path
    }

    /// Agent 已经能通过 `fallbackChain` 读到同名 skill（符号链接或 canonical 副本）？
    /// 若能，则不必再在 `linkURL` 位置建立冗余 symlink。
    public func canInherit(target: URL, linkURL: URL, fallbackChain: [URL]) -> Bool {
        let fm = FileManager.default
        let name = linkURL.lastPathComponent
        let resolvedTarget = target.resolvingSymlinksInPath().path
        for fallback in fallbackChain {
            let candidate = fallback.appendingPathComponent(name)
            if let raw = try? fm.destinationOfSymbolicLink(atPath: candidate.path) {
                let absolute =
                    raw.hasPrefix("/")
                    ? URL(fileURLWithPath: raw)
                    : candidate.deletingLastPathComponent().appendingPathComponent(raw)
                if absolute.resolvingSymlinksInPath().path == resolvedTarget {
                    return true
                }
                continue
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                if candidate.resolvingSymlinksInPath().path == resolvedTarget {
                    return true
                }
            }
        }
        return false
    }

    /// 撤销某一处 Skillport 能证明由自己管理的"安装"：
    /// - 不存在：no-op。
    /// - 是 symlink 且指向 `canonical`：unlink。
    /// - 是 symlink 但指向其它：no-op（可能是用户手工建立的 link，不冒险）。
    /// - 是真实文件 / 目录：no-op（无法证明 ownership，不删除用户目录）。
    public func removeInstallation(at path: URL, canonical: URL) throws {
        let fm = FileManager.default
        if let raw = try? fm.destinationOfSymbolicLink(atPath: path.path) {
            let target =
                raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw)
                : path.deletingLastPathComponent().appendingPathComponent(raw)
            if target.resolvingSymlinksInPath().path == canonical.resolvingSymlinksInPath().path {
                try fm.removeItem(at: path)
            }
            return
        }
    }
}
