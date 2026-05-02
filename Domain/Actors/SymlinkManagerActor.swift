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
}
