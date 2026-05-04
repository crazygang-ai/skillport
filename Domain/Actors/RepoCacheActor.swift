import Foundation
import CryptoKit

/// 为同一个 `(url, ref)` 维护共享 shallow clone 目录，供 Installer（多 skill 扫描）
/// 与 Updater（算远端 subdir tree hash）复用，并合并并发调用。
///
/// 首次 `acquire` → `git clone --depth 1`；之后 `acquire` → `git fetch` + 强制同步到 origin 的 ref。
public actor RepoCacheActor {
    private let git: GitActor
    private let root: URL
    private var inflight: [String: Task<URL, Error>] = [:]

    public init(
        git: GitActor,
        root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillport-repos", isDirectory: true)
    ) {
        self.git = git
        self.root = root
    }

    /// 返回一个已同步到 `(url, ref)` 的本地 repo 路径。
    public func acquire(url: URL, ref: String) async throws -> URL {
        let key = Self.cacheKey(url: url, ref: ref)
        if let running = inflight[key] {
            return try await running.value
        }
        let task = Task<URL, Error> { [git, root] in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let dest = root.appendingPathComponent(key, isDirectory: true)
            let fm = FileManager.default
            let gitDir = dest.appendingPathComponent(".git")
            let isCached = fm.fileExists(atPath: gitDir.path)
            if isCached {
                // 复用：fetch + 强制同步到 origin 的 ref。
                // 如果 fetch/reset 失败 —— 不盲目 re-clone（可能在网络故障时把本地缓存
                // 也清掉），直接抛错让调用方处理（比如 Updater.checkStatus 回落到弱判断）。
                try await git.fetch(in: dest, ref: Self.normalizedRemoteRef(ref))
                try await git.resetHard(in: dest, ref: Self.targetRef(ref))
            } else {
                // 确保目录为空
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try await git.clone(url: url, to: dest, ref: ref, depth: 1)
            }
            return dest
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        return try await task.value
    }

    /// 清空所有缓存目录。由 AppContainer 在退出时调用。
    public func cleanupAll() {
        try? FileManager.default.removeItem(at: root)
        inflight.removeAll()
    }

    /// 生成稳定的目录名：对 `url|ref` 取 SHA256 前 16 字节。
    /// 用 hash 而不是 sanitize 字符串，避免长度和特殊字符问题。
    static func cacheKey(url: URL, ref: String) -> String {
        let raw = url.absoluteString + "|" + ref
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }

    /// `git fetch` 需要的 refspec。空/HEAD 时用默认（origin 的 HEAD）。
    private static func normalizedRemoteRef(_ ref: String) -> String? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "HEAD" { return nil }
        return trimmed
    }

    /// `git reset --hard` 的目标。空/HEAD 用 `FETCH_HEAD`；显式 ref 用 `origin/<ref>`。
    private static func targetRef(_ ref: String) -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "HEAD" { return "FETCH_HEAD" }
        return "origin/\(trimmed)"
    }
}
