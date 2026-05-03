import Foundation
import Testing

@testable import Skillport

@Suite("RSCPayloadParser — skills.sh leaderboard extraction")
struct RSCPayloadParserTests {
    // MARK: - Double-escaped array extraction

    @Test("extractDoubleEscapedArray returns nil if payload doesn't start with [")
    func extractRejectsNonArrayStart() {
        let payload = "garbage"
        let result = RSCPayloadParser.extractDoubleEscapedArray(in: payload, startingAt: 0)
        #expect(result == nil)
    }

    @Test("extractDoubleEscapedArray handles empty array")
    func extractEmptyArray() {
        let payload = "[]"
        let result = RSCPayloadParser.extractDoubleEscapedArray(in: payload, startingAt: 0)
        #expect(result == "[]")
    }

    @Test("extractDoubleEscapedArray handles nested arrays")
    func extractNested() {
        let payload = "[1,[2,3],4]trailing"
        let result = RSCPayloadParser.extractDoubleEscapedArray(in: payload, startingAt: 0)
        #expect(result == "[1,[2,3],4]")
    }

    @Test("extractDoubleEscapedArray respects double-escaped string boundaries")
    func extractWithEscapedStrings() {
        // 内部 JSON 字符串用 \" 包裹; 字符串内的 [ ] 不算数组层级
        let payload = #"[\"a[b]c\",\"d\"]"#
        let result = RSCPayloadParser.extractDoubleEscapedArray(in: payload, startingAt: 0)
        #expect(result == #"[\"a[b]c\",\"d\"]"#)
    }

    @Test("extractDoubleEscapedArray treats \\\\ as literal backslash not escape prefix")
    func extractHandlesBackslashPair() {
        // \\\" 在 payload 层应拆为 \\ + \" = 字面反斜杠 + 字符串终止
        let payload = #"[\"a\\\",\"b\"]"#
        let result = RSCPayloadParser.extractDoubleEscapedArray(in: payload, startingAt: 0)
        #expect(result == #"[\"a\\\",\"b\"]"#)
    }

    @Test("extractDoubleEscapedArray returns nil for unterminated array")
    func extractUnterminated() {
        let payload = "[1,2,3"
        let result = RSCPayloadParser.extractDoubleEscapedArray(in: payload, startingAt: 0)
        #expect(result == nil)
    }

    // MARK: - End-to-end leaderboard parsing

    @Test("parseLeaderboardHTML on empty HTML yields empty result")
    func emptyHTML() {
        let result = RSCPayloadParser.parseLeaderboardHTML("")
        #expect(result.skills.isEmpty)
        #expect(result.totalCount == 0)
    }

    @Test("parseLeaderboardHTML on HTML without initialSkills marker yields empty")
    func htmlWithoutMarker() {
        let result = RSCPayloadParser.parseLeaderboardHTML("<html><body>no marker</body></html>")
        #expect(result.skills.isEmpty)
    }

    @Test("parseLeaderboardHTML extracts skills from real skills.sh fixture")
    func realFixture() throws {
        let url = try #require(
            TestBundleLocator.bundle.url(
                forResource: "skills-sh-leaderboard-alltime", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let result = RSCPayloadParser.parseLeaderboardHTML(html)
        // 实际条数随 skills.sh 增减; 只断言"至少一条"+"totalCount 存在"
        #expect(result.skills.count > 0)
        #expect(result.totalCount >= result.skills.count)
        let first = try #require(result.skills.first)
        #expect(!first.id.isEmpty)
        #expect(!first.source.isEmpty)
        #expect(!first.skillId.isEmpty)
        #expect(first.installs >= 0)
    }

    @Test("parseLeaderboardHTML gracefully degrades on malformed initialSkills")
    func malformedInitialSkills() {
        let html = #"something \"initialSkills\":[malformed"#
        let result = RSCPayloadParser.parseLeaderboardHTML(html)
        #expect(result.skills.isEmpty)
        #expect(result.totalCount == 0)
    }
}
