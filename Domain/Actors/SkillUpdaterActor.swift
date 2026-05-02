import Foundation

public actor SkillUpdaterActor {
    private let git: GitActor
    private let cache: CommitHashCache

    public init(git: GitActor, cache: CommitHashCache) {
        self.git = git
        self.cache = cache
    }

    public func checkStatus(name: String, source: SkillSource, canonical: URL) async throws
        -> UpdateStatus
    {
        switch source {
        case .local, .registry:
            return .upToDate
        case .github(let owner, let repo, let ref):
            let id = SkillIdentity.compute(name: name, source: source)
            let url = URL(string: "https://github.com/\(owner)/\(repo).git")!
            let remoteHash: String
            do {
                remoteHash = try await git.remoteTreeHash(url: url, ref: "refs/heads/\(ref)")
            } catch {
                // 远程不可达：回落到 cache
                if let cached = await cache.get(identity: id),
                    let head = try? await git.headHash(in: canonical),
                    cached == head
                {
                    return .upToDate
                }
                return .unknown
            }
            let localHead = (try? await git.headHash(in: canonical)) ?? ""
            if !remoteHash.isEmpty, remoteHash == localHead {
                try? await cache.set(identity: id, hash: remoteHash)
                return .upToDate
            }
            return .available(remoteHash: remoteHash)
        }
    }

    public func pull(name: String, canonical: URL) async throws {
        try await git.pull(in: canonical)
    }
}
