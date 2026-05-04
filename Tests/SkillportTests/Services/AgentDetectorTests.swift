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

    @Test("detectAllStatuses marks agent installed when only configDir exists (no PATH binary)")
    func statusesConfigDirFallback() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        // codex 二进制不在 PATH，但 `~/.codex` 存在 → should still be isInstalled
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let emptyBin = try dir.mkdir("emptybin")
        let detector = AgentDetector(pathOverride: emptyBin.path)
        let map = try await detector.detectAllStatuses(home: home)
        let codex = map[.codex] ?? .uninstalled
        #expect(codex.binaryOnPath == false)
        #expect(codex.configDirExists == true)
        #expect(codex.isInstalled == true)
        // claudeCode 没 configDir 也没 binary → uninstalled
        #expect(map[.claudeCode]?.isInstalled == false)
    }

    @Test("detectAllStatuses counts skills under skillsDir")
    func statusesSkillCount() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let home = try dir.mkdir("home")
        let claudeSkills = home.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: claudeSkills.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeSkills.appendingPathComponent("b"), withIntermediateDirectories: true)
        let emptyBin = try dir.mkdir("emptybin")
        let detector = AgentDetector(pathOverride: emptyBin.path)
        let map = try await detector.detectAllStatuses(home: home)
        #expect(map[.claudeCode]?.skillsDirExists == true)
        #expect(map[.claudeCode]?.skillCount == 2)
    }
}
