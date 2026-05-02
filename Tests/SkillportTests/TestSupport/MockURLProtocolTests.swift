import Foundation
import Testing

@testable import Skillport

@Suite("MockURLProtocol", .serialized)
struct MockURLProtocolTests {
    @Test("Registered handler returns stubbed response")
    func stubbedResponse() async throws {
        await MockURLProtocol.reset()
        await MockURLProtocol.stub(url: URL(string: "https://example.test/a")!) { _ in
            MockURLProtocol.Response(
                statusCode: 200,
                headers: ["Content-Type": "text/plain"],
                body: Data("hello".utf8)
            )
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(from: URL(string: "https://example.test/a")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "hello")
    }

    @Test("Unregistered URL returns 404")
    func unregisteredReturns404() async throws {
        await MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        let (_, response) = try await session.data(from: URL(string: "https://nowhere.test/x")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }
}
