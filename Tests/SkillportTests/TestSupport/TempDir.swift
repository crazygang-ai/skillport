import Foundation

/// 测试用临时目录；不 mock 文件系统，所有 actor 测试都跑真实 IO。
public struct TempDir: Sendable {
    public let url: URL

    public static func create() throws -> TempDir {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("skillport-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return TempDir(url: base)
    }

    public func cleanup() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// 便利：在 TempDir 下创建子目录。
    @discardableResult
    public func mkdir(_ relative: String) throws -> URL {
        let dir = url.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 便利：写文件。
    @discardableResult
    public func write(_ relative: String, content: String) throws -> URL {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
