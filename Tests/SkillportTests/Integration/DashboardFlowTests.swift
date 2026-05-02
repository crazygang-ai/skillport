import Foundation
import Testing

@testable import Skillport

@Suite("DashboardFlow")
@MainActor
struct DashboardFlowTests {
    @Test("full import → toggle → scan cycle keeps disk and model consistent")
    func fullCycle() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        // 准备一个外部 skill 文件夹
        let external = try dir.mkdir("external/my-skill")
        try "---\ndescription: integration test skill\n---\n# body\n".write(
            to: external.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )

        let container = AppContainer(home: dir.url)
        try await container.skillsModel.refresh()
        #expect(container.skillsModel.skills.isEmpty)

        // 导入
        let installed = try await container.skillsModel.installLocal(
            from: external, installTo: [.claudeCode])
        #expect(installed.name == "my-skill")

        try await container.skillsModel.refresh()
        #expect(container.skillsModel.skills.count == 1)
        let skill = container.skillsModel.skills[0]
        #expect(skill.installedAgents.contains(.claudeCode))

        // 切换 agent：开 cursor、关 claudeCode
        try await container.skillsModel.toggle(
            skillName: "my-skill", agent: .cursor, install: true)
        try await container.skillsModel.toggle(
            skillName: "my-skill", agent: .claudeCode, install: false)
        try await container.skillsModel.refresh()
        let after = container.skillsModel.skills.first!
        #expect(after.installedAgents.contains(.cursor))
        #expect(!after.installedAgents.contains(.claudeCode))

        // 磁盘验证
        let cursorLink = dir.url.appendingPathComponent(".cursor/skills/my-skill")
        #expect(FileManager.default.fileExists(atPath: cursorLink.path))
        let claudeLink = dir.url.appendingPathComponent(".claude/skills/my-skill")
        #expect(!FileManager.default.fileExists(atPath: claudeLink.path))

        // Uninstall 清理
        try await container.skillsModel.uninstall(name: "my-skill")
        try await container.skillsModel.refresh()
        #expect(container.skillsModel.skills.isEmpty)
    }
}
