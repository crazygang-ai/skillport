import Foundation

public actor LockFileActor {
    public struct ReadResult: Sendable {
        public let lockFile: LockFile
        public let recoveryError: SkillportError?
        public let backupURL: URL?
    }

    private let path: URL

    public init(path: URL) {
        self.path = path
    }

    public func read() throws -> LockFile {
        let result = try readWithRecoveryNotice()
        return result.lockFile
    }

    public func readWithRecoveryNotice() throws -> ReadResult {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return ReadResult(
                lockFile: LockFile(version: LockFile.currentVersion, skills: []),
                recoveryError: nil,
                backupURL: nil
            )
        }
        let data = try Data(contentsOf: path)
        do {
            return ReadResult(
                lockFile: try LockFile.decode(from: data),
                recoveryError: nil,
                backupURL: nil
            )
        } catch {
            // 坏文件或不认识的 schema —— 把它挪到旁边 `.bak-<timestamp>` 备份，
            // 返回空 lockfile 让 UI 继续跑；下次 upsert 会写一份干净的。
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = path.appendingPathExtension("bak-\(stamp)")
            try? FileManager.default.moveItem(at: path, to: backup)
            let reason = "\(error)"
            return ReadResult(
                lockFile: LockFile(version: LockFile.currentVersion, skills: []),
                recoveryError: .invalidLockFile(reason: reason),
                backupURL: backup
            )
        }
    }

    public func write(_ lock: LockFile) throws {
        let data = try lock.encode()
        try writeAtomically(data: data, to: path)
    }

    public func upsert(_ skill: LockedSkill) throws {
        var lock = try read()
        lock.skills.removeAll { $0.name == skill.name }
        lock.skills.append(skill)
        try write(lock)
    }

    public func remove(name: String) throws {
        var lock = try read()
        lock.skills.removeAll { $0.name == name }
        try write(lock)
    }

    private func writeAtomically(data: Data, to destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = destination.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: destination)
        }
    }
}
