import Foundation

public actor SymlinkManagerActor {
    public init() {}

    public func link(target: URL, at linkURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: linkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: linkURL.path) {
            if let existing = try? fm.destinationOfSymbolicLink(atPath: linkURL.path) {
                if existing == target.path { return }  // idempotent
                try fm.removeItem(at: linkURL)
            } else {
                throw SkillportError.fileIO(path: linkURL, reason: "path exists and is not a symlink")
            }
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
                let absolute = raw.hasPrefix("/")
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

    /// 撤销某一处"安装"，不关心是 symlink 还是 copy：
    /// - 不存在：no-op。
    /// - 是 symlink 且指向 `canonical`：unlink。
    /// - 是 symlink 但指向其它：no-op（可能是用户手工建立的 link，不冒险）。
    /// - 是真实文件 / 目录：识别为 copy-type，`rm -rf`。
    public func removeInstallation(at path: URL, canonical: URL) throws {
        let fm = FileManager.default
        if let raw = try? fm.destinationOfSymbolicLink(atPath: path.path) {
            let target = raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw)
                : path.deletingLastPathComponent().appendingPathComponent(raw)
            if target.resolvingSymlinksInPath().path == canonical.resolvingSymlinksInPath().path {
                try fm.removeItem(at: path)
            }
            return
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path.path, isDirectory: &isDir) {
            // 普通文件或 copy-type 目录：直接删。调用方负责验证它是一个 skill 安装。
            try fm.removeItem(at: path)
        }
    }
}
