import Foundation

public struct DirectoryReplacement: Sendable {
    public let destination: URL
    public let backup: URL?
    public let hadExistingDestination: Bool

    public func commit() throws {
        guard let backup, FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.removeItem(at: backup)
    }

    public func rollback() throws {
        let fm = FileManager.default
        if hadExistingDestination {
            guard let backup, fm.fileExists(atPath: backup.path) else { return }
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: backup, to: destination)
        } else if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
    }
}

public enum DirectoryReplacer {
    public static func replaceDirectory(
        at destination: URL,
        withStagedDirectory staged: URL,
        backupName: String? = nil
    ) throws -> DirectoryReplacement {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: staged.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillportError.fileIO(path: staged, reason: "staged directory does not exist")
        }

        let hadExistingDestination = fm.fileExists(atPath: destination.path)
        guard hadExistingDestination else {
            try fm.moveItem(at: staged, to: destination)
            return DirectoryReplacement(
                destination: destination,
                backup: nil,
                hadExistingDestination: false
            )
        }

        let parent = destination.deletingLastPathComponent()
        let finalBackupName =
            backupName ?? ".\(destination.lastPathComponent).bak-\(UUID().uuidString)"
        _ = try fm.replaceItemAt(
            destination,
            withItemAt: staged,
            backupItemName: finalBackupName,
            options: [.withoutDeletingBackupItem]
        )
        return DirectoryReplacement(
            destination: destination,
            backup: parent.appendingPathComponent(finalBackupName, isDirectory: true),
            hadExistingDestination: true
        )
    }
}
