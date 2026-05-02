import Foundation
import Testing

@testable import Skillport

@Suite("AppContainer")
@MainActor
struct AppContainerTests {
    @Test("Creates all models and actors without throwing")
    func createsGraph() {
        let dir = try! TempDir.create()
        defer { try? dir.cleanup() }
        let container = AppContainer(home: dir.url)
        #expect(container.home == dir.url)
        #expect(container.skillsModel.agents.count == AgentID.allCases.count)
    }
}
