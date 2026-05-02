import Foundation

public actor CommitHashCache {
    private let path: URL
    private var cache: [String: String]?

    public init(path: URL) {
        self.path = path
    }

    public func get(identity: SkillIdentity) -> String? {
        loadIfNeeded()
        return cache?[identity.rawValue]
    }

    public func set(identity: SkillIdentity, hash: String) throws {
        loadIfNeeded()
        cache?[identity.rawValue] = hash
        try persist()
    }

    public func remove(identity: SkillIdentity) throws {
        loadIfNeeded()
        cache?.removeValue(forKey: identity.rawValue)
        try persist()
    }

    private func loadIfNeeded() {
        if cache != nil { return }
        guard FileManager.default.fileExists(atPath: path.path),
            let data = try? Data(contentsOf: path),
            let map = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            cache = [:]
            return
        }
        cache = map
    }

    private func persist() throws {
        guard let cache else { return }
        let data = try JSONEncoder().encode(cache)
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = path.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: path.path) {
            _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: path)
        }
    }
}
