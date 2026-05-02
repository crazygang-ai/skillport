import Foundation

/// 测试用 URLProtocol，允许按 URL 注册响应。
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

    // MARK: - Thread-safe store (NSLock, no actor)
    // Rationale: URLProtocol.startLoading() is called on an unspecified thread;
    // URLProtocolClient is non-Sendable, so capturing it in a `Task {}` closure
    // is rejected by Swift 6 strict concurrency. An NSLock-guarded dict avoids
    // the Task+Sendable ordeal entirely while remaining thread-safe.
    // nonisolated(unsafe) suppresses the "nonisolated global shared mutable state"
    // error; safety is enforced by _lock.
    private nonisolated(unsafe) static let _lock = NSLock()
    private nonisolated(unsafe) static var _handlers: [URL: Handler] = [:]

    public static func stub(url: URL, handler: @escaping Handler) async {
        _lock.withLock { _handlers[url] = handler }
    }

    public static func reset() async {
        _lock.withLock { _handlers.removeAll() }
    }

    // MARK: - URLProtocol overrides

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let request = self.request
        let handler: Handler? = Self._lock.withLock { Self._handlers[request.url ?? URL(fileURLWithPath: "/")] }
        let resp: Response
        if let handler {
            resp = handler(request)
        } else {
            resp = Response(statusCode: 404, headers: [:], body: Data())
        }
        let http = HTTPURLResponse(
            url: request.url!,
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
