import Foundation

public struct LocalImporter: Sendable {
    public init() {}

    public func importSkill(from source: URL, home: URL) throws -> URL {
        let fm = FileManager.default
        let skillMd = source.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMd.path) else {
            throw SkillportError.fileIO(path: source, reason: "no SKILL.md in source folder")
        }
        if let symlink = try Self.firstSymlink(in: source) {
            throw SkillportError.fileIO(
                path: symlink,
                reason: "local import refuses source trees containing symlinks"
            )
        }
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: canonicalBase, withIntermediateDirectories: true)
        let dest = canonicalBase.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw SkillportError.fileIO(path: dest, reason: "destination already exists")
        }
        let tmp = canonicalBase.appendingPathComponent(
            ".\(source.lastPathComponent).tmp-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fm.copyItem(at: source, to: tmp)
            guard fm.fileExists(atPath: tmp.appendingPathComponent("SKILL.md").path) else {
                throw SkillportError.fileIO(path: tmp, reason: "copied skill missing SKILL.md")
            }
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
        return dest
    }

    private static func firstSymlink(in url: URL) throws -> URL? {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true {
            return url
        }
        guard values.isDirectory == true else {
            return nil
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for entry in entries {
            if let symlink = try firstSymlink(in: entry) {
                return symlink
            }
        }
        return nil
    }
}
