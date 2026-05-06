import Darwin
import Foundation

public actor LockFileActor {
    public struct ReadResult: Sendable {
        public let lockFile: LockFile
        public let recoveryError: SkillportError?
        public let backupURL: URL?
    }

    private let path: URL
    private let lockPath: URL
    private static let lockTimeout: TimeInterval = 5
    private static let staleLockInterval: TimeInterval = 30

    public init(path: URL) {
        self.path = path
        self.lockPath = path.appendingPathExtension("lock")
    }

    public func read() throws -> LockFile {
        let result = try readWithRecoveryNotice()
        return result.lockFile
    }

    public func readWithRecoveryNotice() throws -> ReadResult {
        try withFileLock {
            try readWithRecoveryNoticeUnlocked()
        }
    }

    public func write(_ lock: LockFile) throws {
        try withFileLock {
            try writeUnlocked(lock)
        }
    }

    public func upsert(_ skill: LockedSkill) throws {
        try withFileLock {
            var lock = try readWithRecoveryNoticeUnlocked().lockFile
            let incomingID = SkillIdentity.compute(name: skill.name, source: skill.source)
            let incomingPath = skill.path.resolvingSymlinksInPath().path
            lock.skills.removeAll {
                SkillIdentity.compute(name: $0.name, source: $0.source) == incomingID
                    || $0.path.resolvingSymlinksInPath().path == incomingPath
            }
            lock.skills.append(skill)
            try writeUnlocked(lock)
        }
    }

    public func remove(name: String) throws {
        try withFileLock {
            var lock = try readWithRecoveryNoticeUnlocked().lockFile
            let originalCount = lock.skills.count
            lock.skills.removeAll { $0.name == name }
            guard lock.skills.count != originalCount else {
                throw SkillportError.unexpected("Skill '\(name)' is not managed by Skillport.")
            }
            try writeUnlocked(lock)
        }
    }

    private func readWithRecoveryNoticeUnlocked() throws -> ReadResult {
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

    private func writeUnlocked(_ lock: LockFile) throws {
        let data = try lock.encode()
        try writeAtomically(data: data, to: path)
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

    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        try acquireFileLock()
        defer { releaseFileLock() }
        return try body()
    }

    private func acquireFileLock() throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: lockPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let deadline = Date().addingTimeInterval(Self.lockTimeout)
        while true {
            let fd = Darwin.open(lockPath.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
            if fd >= 0 {
                let pid = Data("\(getpid())".utf8)
                _ = pid.withUnsafeBytes { buffer in
                    Darwin.write(fd, buffer.baseAddress, buffer.count)
                }
                Darwin.close(fd)
                return
            }

            let code = errno
            if code != EEXIST {
                throw SkillportError.fileIO(
                    path: lockPath,
                    reason: "failed to acquire lock: \(String(cString: strerror(code)))"
                )
            }

            removeStaleLockIfNeeded()
            if Date() >= deadline {
                throw SkillportError.fileIO(path: lockPath, reason: "timed out acquiring lock")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func removeStaleLockIfNeeded() {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: lockPath.path),
            let modified = attrs[.modificationDate] as? Date,
            Date().timeIntervalSince(modified) > Self.staleLockInterval
        else {
            return
        }
        try? FileManager.default.removeItem(at: lockPath)
    }

    private func releaseFileLock() {
        try? FileManager.default.removeItem(at: lockPath)
    }
}
