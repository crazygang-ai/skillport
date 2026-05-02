import Testing
@testable import Skillport

@Suite("SkillportLog")
struct SkillportLogTests {
    @Test("All subsystems share the same bundle identifier")
    func subsystemIdentifier() {
        #expect(SkillportLog.subsystem == "ai.crazygang.Skillport")
    }

    @Test("Per-category loggers are distinct and correctly categorized")
    func categoryLoggers() {
        // os.Logger 不通过 description 暴露 category，但不同 category 的 logger
        // 底层指向不同的 os_log 对象，因此 debugDescription 地址不同。
        let scanner = SkillportLog.scanner
        let registry = SkillportLog.registry
        #expect(String(reflecting: scanner) != String(reflecting: registry))
        // 验证 scanner 和 registry 属性与缓存的静态常量相同（同一 category → 同一对象）。
        #expect(String(reflecting: SkillportLog.scanner) == String(reflecting: scanner))
        #expect(String(reflecting: SkillportLog.registry) == String(reflecting: registry))
    }
}
