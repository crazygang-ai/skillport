import Testing

@testable import Skillport

@Suite("UpdateStatus")
struct UpdateStatusTests {
    @Test("upToDate has no payload")
    func upToDate() {
        let s = UpdateStatus.upToDate
        #expect(s.isUpToDate)
        #expect(s.pendingRemoteHash == nil)
    }

    @Test("available carries remote hash")
    func availableHash() {
        let s = UpdateStatus.available(remoteHash: "abc123")
        #expect(!s.isUpToDate)
        #expect(s.pendingRemoteHash == "abc123")
    }

    @Test("unknown is neither up-to-date nor has hash")
    func unknown() {
        let s = UpdateStatus.unknown
        #expect(!s.isUpToDate)
        #expect(s.pendingRemoteHash == nil)
    }
}
