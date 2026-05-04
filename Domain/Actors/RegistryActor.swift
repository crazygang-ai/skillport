import Foundation
import OSLog

public actor RegistryActor {
    private let session: URLSession
    private let baseURL: URL
    private let cacheTTL: TimeInterval
    private var leaderboardCache: [LeaderboardCategory: (result: LeaderboardResult, at: Date)] = [:]
    private let logger = Logger(subsystem: "ai.crazygang.Skillport", category: "registry")

    public init(
        session: URLSession,
        baseURL: URL = URL(string: "https://skills.sh")!,
        cacheTTL: TimeInterval = 5 * 60
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cacheTTL = cacheTTL
    }

    // MARK: - Leaderboard

    public func leaderboard(_ category: LeaderboardCategory) async throws -> LeaderboardResult {
        if let cached = leaderboardCache[category],
            Date().timeIntervalSince(cached.at) < cacheTTL
        {
            return cached.result
        }
        let path = category.urlPath.isEmpty ? "/" : category.urlPath
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SkillportError.networkFailed(url: url, reason: "status \(http.statusCode)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw SkillportError.parseFailed(file: nil, reason: "non-utf8 response from \(url)")
        }
        let result = RSCPayloadParser.parseLeaderboardHTML(html)
        leaderboardCache[category] = (result, Date())
        return result
    }

    public func invalidateLeaderboardCache(_ category: LeaderboardCategory? = nil) {
        if let c = category {
            leaderboardCache.removeValue(forKey: c)
        } else {
            leaderboardCache.removeAll()
        }
    }

    // MARK: - Search

    public func search(query: String, limit: Int = 50) async throws -> [RegistrySkill] {
        let clampedLimit = min(max(1, limit), 500)
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/search"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(clampedLimit)),
        ]
        let url = comps.url!
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SkillportError.networkFailed(url: url, reason: "status \(http.statusCode)")
        }
        struct Response: Decodable {
            let skills: [RawSkill]?
            struct RawSkill: Decodable {
                let id: String
                let skillId: String?
                let name: String?
                let installs: Int
                let source: String
                let installsYesterday: Int?
                let change: Int?

                enum CodingKeys: String, CodingKey {
                    case id, skillId, name, installs, source, change
                    case installsYesterday = "installs_yesterday"
                }
            }
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SkillportError.parseFailed(file: nil, reason: "\(error)")
        }
        return (decoded.skills ?? []).map { raw in
            let skillId = raw.skillId ?? URL(string: raw.id)?.lastPathComponent ?? raw.id
            return RegistrySkill(
                id: raw.id,
                skillId: skillId,
                name: raw.name ?? skillId,
                installs: raw.installs,
                source: raw.source,
                installsYesterday: raw.installsYesterday,
                change: raw.change
            )
        }
    }
}
