import Foundation
import OSLog

/// 从 skills.sh 的 Next.js RSC flight payload 里提取 `initialSkills` 数组。
///
/// 逻辑 1:1 port 自 Electron 版 `electron/services/skill-registry-service.ts` 的
/// `parseLeaderboardHTML` + `extractDoubleEscapedArray` + `decodeDoubleEscapedJson`。
/// skills.sh 没有公开 JSON API, 必须靠抓 HTML 里的序列化 state 树。
/// 此 parser 对 payload 格式变化脆弱; 生产故障时靠空列表降级, 不 throw。
public enum RSCPayloadParser {
    private static let logger = Logger(subsystem: "ai.crazygang.Skillport", category: "registry")
    private static let marker = #"\"initialSkills\":"#
    private static let totalMarker = #"\"totalSkills\":"#

    public static func parseLeaderboardHTML(_ html: String) -> LeaderboardResult {
        guard let markerRange = html.range(of: marker) else {
            return LeaderboardResult()
        }
        let distance = html.distance(from: html.startIndex, to: markerRange.upperBound)
        guard let rawChunk = extractDoubleEscapedArray(in: html, startingAt: distance) else {
            logger.warning("initialSkills marker found but array could not be extracted")
            return LeaderboardResult()
        }
        let decoded: String
        do {
            decoded = try decodeDoubleEscapedJson(rawChunk)
        } catch {
            logger.warning("failed to decode RSC double-escape: \(error.localizedDescription)")
            return LeaderboardResult()
        }
        guard let data = decoded.data(using: .utf8) else { return LeaderboardResult() }
        let raw: [[String: Any]]
        do {
            raw = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        } catch {
            logger.warning("failed to parse decoded JSON: \(error.localizedDescription)")
            return LeaderboardResult()
        }
        let total = extractTotalCount(in: html) ?? raw.count
        let skills = raw.compactMap(mapRawSkill)
        return LeaderboardResult(skills: skills, totalCount: total)
    }

    // MARK: - State machine

    /// 单遍状态机, 从 `[` 开始扫到匹配的 `]`。返回切片 [start, end], 含首尾 []。
    /// 参考 Electron 版注释:
    ///   - `\\` → 字面反斜杠 (原子消费两字符)
    ///   - `\"` → 内部 JSON 字符串分隔符 (切换 inString 状态)
    public static func extractDoubleEscapedArray(in html: String, startingAt offset: Int) -> String? {
        let chars = Array(html)
        guard offset < chars.count, chars[offset] == "[" else { return nil }

        var depth = 0
        var inString = false
        var i = offset

        while i < chars.count {
            let c = chars[i]
            let next: Character? = (i + 1 < chars.count) ? chars[i + 1] : nil

            if inString {
                if c == "\\" && next == "\\" {
                    i += 2
                } else if c == "\\" && next == "\"" {
                    inString = false
                    i += 2
                } else {
                    i += 1
                }
            } else {
                if c == "\\" && next == "\"" {
                    inString = true
                    i += 2
                } else if c == "[" {
                    depth += 1
                    i += 1
                } else if c == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(chars[offset...i])
                    }
                    i += 1
                } else {
                    i += 1
                }
            }
        }
        return nil
    }

    // MARK: - Decoding

    /// 用 JSONDecoder 把 RSC 的"双重转义"字符串还原一层 — 与 Electron 版
    /// `JSON.parse('"' + rawChunk + '"')` 等价。
    public static func decodeDoubleEscapedJson(_ rawChunk: String) throws -> String {
        let wrapped = "\"\(rawChunk)\""
        guard let data = wrapped.data(using: .utf8) else {
            throw SkillportError.parseFailed(file: nil, reason: "utf8 encode failed")
        }
        return try JSONDecoder().decode(String.self, from: data)
    }

    // MARK: - Raw skill mapping

    private static func mapRawSkill(_ item: [String: Any]) -> RegistrySkill? {
        let id: String = {
            if let explicit = item["id"] as? String, !explicit.isEmpty { return explicit }
            if let source = item["source"] as? String, let skillId = item["skillId"] as? String {
                return "\(source)/\(skillId)"
            }
            return ""
        }()
        if id.isEmpty { return nil }
        let skillId = (item["skillId"] as? String) ?? ""
        let name = (item["name"] as? String) ?? skillId
        let source = (item["source"] as? String) ?? ""
        let installs = (item["installs"] as? Int) ?? Int((item["installs"] as? Double) ?? 0)
        let installsYesterday = (item["installs_yesterday"] as? Int)
        let change = (item["change"] as? Int)
        return RegistrySkill(
            id: id,
            skillId: skillId,
            name: name,
            installs: installs,
            source: source,
            installsYesterday: installsYesterday,
            change: change
        )
    }

    private static func extractTotalCount(in html: String) -> Int? {
        guard let r = html.range(of: totalMarker) else { return nil }
        let tail = html[r.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }
}
