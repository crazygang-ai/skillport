import Foundation

public actor LockFileActor {
    private let path: URL

    public init(path: URL) {
        self.path = path
    }

    public func read() throws -> LockFile {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return LockFile(version: LockFile.currentVersion, skills: [])
        }
        let data = try Data(contentsOf: path)
        do {
            return try LockFile.decode(from: data)
        } catch let LockFile.DecodingError.unsupportedVersion(v) {
            throw SkillportError.invalidLockFile(reason: "unsupported version \(v)")
        } catch {
            throw SkillportError.invalidLockFile(reason: "\(error)")
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
