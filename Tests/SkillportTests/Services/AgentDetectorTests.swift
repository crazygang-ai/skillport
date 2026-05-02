import Foundation
import Testing

@testable import Skillport

@Suite("AgentDetector")
struct AgentDetectorTests {
    @Test("Detects a fake binary placed on a custom PATH")
    func detectsOnCustomPath() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        // 创建一个名为 "claude" 的可执行空文件
        let fakeBin = dir.url.appendingPathComponent("claude")
        try "#!/bin/sh\nexit 0\n".write(to: fakeBin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fakeBin.path)

        let detector = AgentDetector(pathOverride: dir.url.path)
        let installed = try await detector.isInstalled(agentID: .claudeCode)
        #expect(installed == true)
    }

    @Test("Returns false for agent whose binary is absent")
    func returnsFalseWhenMissing() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let detector = AgentDetector(pathOverride: dir.url.path)
        let installed = try await detector.isInstalled(agentID: .kiro)
        #expect(installed == false)
    }

    @Test("detectAll returns map keyed by AgentID")
    func detectAll() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let bin = dir.url.appendingPathComponent("cursor")
        try "".write(to: bin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        let detector = AgentDetector(pathOverride: dir.url.path)
        let map = try await detector.detectAll()
        #expect(map[.cursor] == true)
        #expect(map[.claudeCode] == false)
        #expect(map.count == AgentID.allCases.count)
    }
}
