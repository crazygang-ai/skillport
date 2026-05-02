import Foundation
import Testing

@testable import Skillport

@Suite("KeychainActor", .serialized)
struct KeychainActorTests {
    let serviceName: String

    init() {
        serviceName = "skillport-test-\(UUID().uuidString)"
    }

    @Test("Set then get returns stored password")
    func setAndGet() async throws {
        let actor = KeychainActor(service: serviceName)
        try await actor.set(account: "proxy", password: "s3cret")
        let back = try await actor.get(account: "proxy")
        #expect(back == "s3cret")
        try await actor.remove(account: "proxy")
    }

    @Test("Get returns nil for missing account")
    func getMissing() async throws {
        let actor = KeychainActor(service: serviceName)
        let back = try await actor.get(account: "does-not-exist")
        #expect(back == nil)
    }

    @Test("Set overwrites existing password")
    func overwrite() async throws {
        let actor = KeychainActor(service: serviceName)
        try await actor.set(account: "a", password: "one")
        try await actor.set(account: "a", password: "two")
        let back = try await actor.get(account: "a")
        #expect(back == "two")
        try await actor.remove(account: "a")
    }

    @Test("Remove deletes entry; subsequent get returns nil")
    func removeEntry() async throws {
        let actor = KeychainActor(service: serviceName)
        try await actor.set(account: "x", password: "y")
        try await actor.remove(account: "x")
        #expect(try await actor.get(account: "x") == nil)
    }
}
