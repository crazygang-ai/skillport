import Foundation

public actor SkillContentFetcher {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// 并发请求多个候选 URL，首个返回 200 的即赢。其它请求会被取消。
    public func fetchFirstSuccess(from urls: [URL]) async throws -> Data {
        guard !urls.isEmpty else {
            throw SkillportError.networkFailed(url: nil, reason: "no candidate urls")
        }
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
            throw SkillportError.networkFailed(url: urls.first, reason: "all candidates failed")
        }
    }
}
