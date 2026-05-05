import Foundation
import OSLog

public actor SkillContentFetcher {
    public static let htmlPrefix = "<!-- HTML -->"

    private let session: URLSession?
    private let proxySettings: ProxySettingsActor?
    private let keychain: KeychainActor?
    private let rawBase: URL
    private let apiBase: URL
    private let skillsShBase: URL
    private let cacheTTL: TimeInterval

    private var contentCache: [String: (content: String, at: Date)] = [:]
    private var githubApiRateLimitResetAt: Date?

    private let logger = Logger(subsystem: "ai.crazygang.Skillport", category: "fetcher")

    public init(
        session: URLSession,
        rawBase: URL = URL(string: "https://raw.githubusercontent.com")!,
        apiBase: URL = URL(string: "https://api.github.com")!,
        skillsShBase: URL = URL(string: "https://skills.sh")!,
        cacheTTL: TimeInterval = 10 * 60
    ) {
        self.session = session
        self.proxySettings = nil
        self.keychain = nil
        self.rawBase = rawBase
        self.apiBase = apiBase
        self.skillsShBase = skillsShBase
        self.cacheTTL = cacheTTL
    }

    public init(
        proxySettings: ProxySettingsActor,
        keychain: KeychainActor? = nil,
        rawBase: URL = URL(string: "https://raw.githubusercontent.com")!,
        apiBase: URL = URL(string: "https://api.github.com")!,
        skillsShBase: URL = URL(string: "https://skills.sh")!,
        cacheTTL: TimeInterval = 10 * 60
    ) {
        self.session = nil
        self.proxySettings = proxySettings
        self.keychain = keychain
        self.rawBase = rawBase
        self.apiBase = apiBase
        self.skillsShBase = skillsShBase
        self.cacheTTL = cacheTTL
    }

    // MARK: - Low-level parallel race (preserved from M1)

    /// 并发请求多个候选 URL，首个返回 200 的即赢。其它请求会被取消。
    public func fetchFirstSuccess(from urls: [URL]) async throws -> Data {
        guard !urls.isEmpty else {
            throw SkillportError.networkFailed(url: nil, reason: "no candidate urls")
        }
        let session = await sessionForRequest()
        return try await withThrowingTaskGroup(of: Data?.self) { group in
            for url in urls {
                group.addTask { [session] in
                    do {
                        let (data, resp) = try await session.data(from: url)
                        if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                            return data
                        }
                        return nil
                    } catch {
                        return nil
                    }
                }
            }
            for try await data in group {
                if let data {
                    group.cancelAll()
                    return data
                }
            }
            throw SkillportError.networkFailed(
                url: urls.first, reason: "all candidates failed")
        }
    }

    // MARK: - Public cascade entry (M5)

    public func fetchContent(source: String, skillId: String) async throws -> String {
        let cacheKey = "\(source)/\(skillId)"
        if let cached = contentCache[cacheKey],
            Date().timeIntervalSince(cached.at) < cacheTTL
        {
            return cached.content
        }

        // Strategy 1: 8 个 raw URL 候选并发 race
        if let raw = try? await fetchFromRawCandidates(source: source, skillId: skillId) {
            contentCache[cacheKey] = (raw, Date())
            return raw
        }

        // Strategy 2: skills.sh RSC payload → HTML
        if let html = try? await fetchFromSkillsSh(source: source, skillId: skillId) {
            let content = Self.htmlPrefix + html
            contentCache[cacheKey] = (content, Date())
            return content
        }

        // Strategy 3: GitHub Tree API discovery
        if let tree = try? await discoverViaTreeAPI(source: source, skillId: skillId) {
            contentCache[cacheKey] = (tree, Date())
            return tree
        }
        return ""
    }

    public func invalidateCache(source: String? = nil, skillId: String? = nil) {
        if let s = source, let k = skillId {
            contentCache.removeValue(forKey: "\(s)/\(k)")
        } else {
            contentCache.removeAll()
        }
    }

    // MARK: - Strategy 1

    private func fetchFromRawCandidates(source: String, skillId: String) async throws -> String {
        let urls = Self.buildCandidateURLs(source: source, skillId: skillId, rawBase: rawBase)
        let data = try await fetchFirstSuccess(from: urls)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SkillportError.parseFailed(file: nil, reason: "non-utf8 raw content")
        }
        return text
    }

    public static func buildCandidateURLs(source: String, skillId: String, rawBase: URL) -> [URL] {
        let branches = ["main", "master"]
        let layouts = [
            "\(skillId)/SKILL.md",
            "skills/\(skillId)/SKILL.md",
            ".claude/skills/\(skillId)/SKILL.md",
            "SKILL.md",
        ]
        return branches.flatMap { branch in
            layouts.compactMap { layout in
                URL(string: "\(rawBase.absoluteString)/\(source)/\(branch)/\(layout)")
            }
        }
    }

    // MARK: - Strategy 2

    private func fetchFromSkillsSh(source: String, skillId: String) async throws -> String {
        let url = skillsShBase.appendingPathComponent(source).appendingPathComponent(skillId)
        var req = URLRequest(url: url)
        req.setValue("text/x-component", forHTTPHeaderField: "Accept")
        req.setValue("1", forHTTPHeaderField: "RSC")
        req.setValue("%5B%22%22%5D", forHTTPHeaderField: "Next-Router-State-Tree")
        req.timeoutInterval = 10
        let session = await sessionForRequest()
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw SkillportError.networkFailed(url: url, reason: "status \(http.statusCode)")
        }
        guard let payload = String(data: data, encoding: .utf8) else {
            throw SkillportError.parseFailed(file: nil, reason: "non-utf8 skills.sh payload")
        }
        return try extractLargestTChunk(in: payload)
    }

    /// 找形如 `{ref}:T{hexSize},{html}` 的块里 size 最大的那段 — skills.sh 在该块塞 SKILL.md 渲染 HTML。
    private func extractLargestTChunk(in payload: String) throws -> String {
        let pattern = #"^\w+:T([0-9a-f]+),"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let ns = payload as NSString
        let range = NSRange(location: 0, length: ns.length)
        var bestOffset = -1
        var bestSize = 0
        regex.enumerateMatches(in: payload, options: [], range: range) { m, _, _ in
            guard let m, m.numberOfRanges >= 2 else { return }
            let hex = ns.substring(with: m.range(at: 1))
            let size = Int(hex, radix: 16) ?? 0
            let afterOffset = m.range.location + m.range.length
            if size > bestSize {
                bestSize = size
                bestOffset = afterOffset
            }
        }
        guard bestOffset >= 0, bestSize >= 50 else {
            throw SkillportError.parseFailed(file: nil, reason: "no suitable T chunk")
        }
        let html = ns.substring(with: NSRange(location: bestOffset, length: bestSize))
        guard html.contains("<") else {
            throw SkillportError.parseFailed(file: nil, reason: "T chunk not HTML")
        }
        return html
    }

    // MARK: - Strategy 3

    private func discoverViaTreeAPI(source: String, skillId: String) async throws -> String {
        if let reset = githubApiRateLimitResetAt, Date() < reset {
            throw SkillportError.networkFailed(url: nil, reason: "github api rate limited")
        }
        for branch in ["main", "master"] {
            let url =
                apiBase
                .appendingPathComponent("repos")
                .appendingPathComponent(source)
                .appendingPathComponent("git/trees")
                .appendingPathComponent(branch)
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "recursive", value: "1")]
            var req = URLRequest(url: comps.url!)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            do {
                let session = await sessionForRequest()
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    updateRateLimit(from: http)
                    if http.statusCode == 403 || http.statusCode == 429 {
                        return ""  // treat as miss
                    }
                    if http.statusCode != 200 { continue }
                }
                struct Tree: Decodable {
                    let tree: [Entry]?
                    struct Entry: Decodable {
                        let path: String
                        let type: String
                    }
                }
                let parsed = try JSONDecoder().decode(Tree.self, from: data)
                guard
                    let match = parsed.tree?.first(where: {
                        $0.type == "blob" && $0.path.hasSuffix("SKILL.md")
                            && $0.path.contains(skillId)
                    })
                else { continue }
                let rawURL =
                    rawBase
                    .appendingPathComponent(source)
                    .appendingPathComponent(branch)
                    .appendingPathComponent(match.path)
                var rawReq = URLRequest(url: rawURL)
                rawReq.timeoutInterval = 10
                let (rawData, rawResp) = try await session.data(for: rawReq)
                if let http = rawResp as? HTTPURLResponse, http.statusCode == 200,
                    let content = String(data: rawData, encoding: .utf8)
                {
                    return content
                }
            } catch {
                logger.warning(
                    "tree API error for \(source) @ \(branch): \(error.localizedDescription)")
                continue
            }
        }
        throw SkillportError.networkFailed(url: nil, reason: "tree api found nothing")
    }

    public func currentConnectionProxySummary() async -> [String: String] {
        if let session {
            return NetworkSession.connectionProxySummary(
                from: session.configuration.connectionProxyDictionary ?? [:])
        }
        guard let proxySettings else { return [:] }
        let password = await proxyPassword()
        let config = await proxySettings.current
        return NetworkSession.connectionProxySummary(proxy: config, password: password)
    }

    private func sessionForRequest() async -> URLSession {
        if let session {
            return session
        }
        guard let proxySettings else {
            return .shared
        }
        let password = await proxyPassword()
        let config = await proxySettings.current
        return NetworkSession.makeSession(proxy: config, password: password)
    }

    private func proxyPassword() async -> String? {
        guard let keychain else { return nil }
        return try? await keychain.get(account: ProxySettingsActor.proxyPasswordAccount)
    }

    private func updateRateLimit(from response: HTTPURLResponse) {
        let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining")
        let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset")
        if remaining == "0", let r = reset, let ts = TimeInterval(r) {
            githubApiRateLimitResetAt = Date(timeIntervalSince1970: ts)
            logger.warning(
                "github api rate limit hit, reset at \(Date(timeIntervalSince1970: ts))")
        }
    }
}
