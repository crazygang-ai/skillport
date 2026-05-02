import Foundation

public struct LocalImporter: Sendable {
    public init() {}

    public func importSkill(from source: URL, home: URL) throws -> URL {
        let fm = FileManager.default
        let skillMd = source.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMd.path) else {
            throw SkillportError.fileIO(path: source, reason: "no SKILL.md in source folder")
        }
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: canonicalBase, withIntermediateDirectories: true)
        let dest = canonicalBase.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw SkillportError.fileIO(path: dest, reason: "destination already exists")
        }
        try fm.copyItem(at: source, to: dest)
        return dest
    }
}
