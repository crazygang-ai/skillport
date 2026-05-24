import Foundation

public struct GitHubRepoReference: Equatable, Sendable {
    public let owner: String
    public let repo: String

    public init(owner: String, repo: String) {
        self.owner = owner
        self.repo = repo
    }

    public var gitURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo).git")!
    }

    public static func parse(_ raw: String) throws -> GitHubRepoReference {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SkillportError.unexpected("GitHub repository is required")
        }

        if trimmed.hasPrefix("git@github.com:") {
            let path = String(trimmed.dropFirst("git@github.com:".count))
            return try parsePath(path)
        }

        if trimmed.hasPrefix("github.com/") {
            return try parsePath(String(trimmed.dropFirst("github.com/".count)))
        }

        if let url = URL(string: trimmed), let scheme = url.scheme {
            guard ["http", "https"].contains(scheme.lowercased()),
                url.host?.lowercased() == "github.com"
            else {
                throw SkillportError.unexpected("Only GitHub repositories are supported")
            }
            return try parsePath(url.path)
        }

        return try parsePath(trimmed)
    }

    private static func parsePath(_ rawPath: String) throws -> GitHubRepoReference {
        let parts =
            rawPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard parts.count >= 2 else {
            throw SkillportError.unexpected("Use owner/repo or a GitHub repository URL")
        }
        let owner = parts[0]
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard isValidComponent(owner), isValidComponent(repo) else {
            throw SkillportError.unexpected("Invalid GitHub repository")
        }
        return GitHubRepoReference(owner: owner, repo: repo)
    }

    private static func isValidComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return value.allSatisfy { ch in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "."
        }
    }
}
