import Foundation

public struct RegistryEntry: Codable, Hashable, Sendable {
    public let slug: String
    public let name: String
    public let category: String

    public init(slug: String, name: String, category: String) {
        self.slug = slug
        self.name = name
        self.category = category
    }
}

public actor RegistryActor {
    private let session: URLSession
    private let listingURL: URL

    public init(
        session: URLSession,
        listingURL: URL = URL(string: "https://skills.sh/api/skills.json")!
    ) {
        self.session = session
        self.listingURL = listingURL
    }

    public func fetchListing() async throws -> [RegistryEntry] {
        let (data, response) = try await session.data(from: listingURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SkillportError.networkFailed(url: listingURL, reason: "status \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode([RegistryEntry].self, from: data)
        } catch {
            throw SkillportError.networkFailed(url: listingURL, reason: "\(error)")
        }
    }

    public nonisolated static func filter(
        entries: [RegistryEntry], query: String, category: String?
    ) -> [RegistryEntry] {
        let q = query.lowercased()
        return entries.filter { entry in
            let matchesQuery =
                q.isEmpty
                || entry.name.lowercased().contains(q)
                || entry.slug.lowercased().contains(q)
            let matchesCat = category.map { $0 == entry.category } ?? true
            return matchesQuery && matchesCat
        }
    }
}
