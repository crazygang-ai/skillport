import Foundation

/// 测试用 URLProtocol，允许按 URL 或谓词注册响应。
/// 所有状态由 NSLock 保护，避免 Swift 6 strict-concurrency 下
/// Task 闭包捕获非 Sendable 类型（URLProtocol / URLProtocolClient）的问题。
/// nonisolated(unsafe) 允许在 Swift 6 strict-concurrency 模式下持有全局可变状态。
public final class MockURLProtocol: URLProtocol {
    public struct Response: Sendable {
        public let statusCode: Int
        public let headers: [String: String]
        public let body: Data

        public init(statusCode: Int, headers: [String: String], body: Data) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    public typealias Handler = @Sendable (URLRequest) -> Response
    public typealias Matcher = @Sendable (URL) -> Bool

    // MARK: - Thread-safe store (NSLock, no actor)

    private static let _lock = NSLock()
    private nonisolated(unsafe) static var _handlers: [URL: Handler] = [:]
    private nonisolated(unsafe) static var _matchers: [(Matcher, Handler)] = []
    private nonisolated(unsafe) static var _requestLog: [URLRequest] = []

    // MARK: - Registration (async variants kept for back-compat)

    public static func stub(url: URL, handler: @escaping Handler) async {
        _lock.withLock { _handlers[url] = handler }
    }

    public static func reset() async {
        _lock.withLock {
            _handlers.removeAll()
            _matchers.removeAll()
            _requestLog.removeAll()
        }
    }

    // MARK: - Registration (sync convenience, M5)

    public static func resetSync() {
        _lock.withLock {
            _handlers.removeAll()
            _matchers.removeAll()
            _requestLog.removeAll()
        }
    }

    public static func stub(
        url: URL,
        status: Int = 200,
        headers: [String: String] = [:],
        body: Data
    ) {
        let h: Handler = { _ in Response(statusCode: status, headers: headers, body: body) }
        _lock.withLock { _handlers[url] = h }
    }

    public static func stub(
        urlMatch: @escaping Matcher,
        status: Int = 200,
        headers: [String: String] = [:],
        body: Data
    ) {
        let h: Handler = { _ in Response(statusCode: status, headers: headers, body: body) }
        _lock.withLock { _matchers.append((urlMatch, h)) }
    }

    public static func stub(
        urlMatch: @escaping Matcher,
        handler: @escaping Handler
    ) {
        _lock.withLock { _matchers.append((urlMatch, handler)) }
    }

    // MARK: - Observation

    public static var requestLog: [URLRequest] {
        _lock.withLock { _requestLog }
    }

    public static func clearRequestLog() {
        _lock.withLock { _requestLog.removeAll() }
    }

    // MARK: - Session helper

    public static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self] + (cfg.protocolClasses ?? [])
        return URLSession(configuration: cfg)
    }

    // MARK: - URLProtocol overrides

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let request = self.request
        let url = request.url ?? URL(fileURLWithPath: "/")

        let resp: Response = Self._lock.withLock {
            Self._requestLog.append(request)
            if let handler = Self._handlers[url] {
                return handler(request)
            }
            for (matcher, handler) in Self._matchers where matcher(url) {
                return handler(request)
            }
            return Response(statusCode: 404, headers: [:], body: Data())
        }

        let http = HTTPURLResponse(
            url: url,
            statusCode: resp.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: resp.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: resp.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {  // no-op
    }
}
