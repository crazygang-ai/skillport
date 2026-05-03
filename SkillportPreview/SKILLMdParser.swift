import Foundation

/// 纯函数：拆分 SKILL.md 的 frontmatter 与 body；序列化反之。
/// 与主 app `Domain/Parsers/SKILLMdParser.swift` 保持 parity；校验见 Scripts/check-parser-parity.sh。
public enum SKILLMdParser {
    public struct ParseResult: Sendable {
        public let metadata: SKILLMetadata
        public let body: String
    }

    public static func parse(_ raw: String) throws -> ParseResult {
        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            return ParseResult(metadata: SKILLMetadata(), body: raw)
        }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var closerIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i] == "---" || lines[i] == "---\r" {
                closerIndex = i
                break
            }
        }
        guard let closer = closerIndex else {
            throw SkillportError.parseFailed(reason: "unclosed frontmatter")
        }
        let yamlLines = lines[1..<closer]
        let yaml = yamlLines.joined(separator: "\n")
        let bodyLines = lines[(closer + 1)...]
        let body = bodyLines.joined(separator: "\n")
        let metadata: SKILLMetadata
        do {
            metadata = try SKILLMetadata.fromYAML(yaml)
        } catch {
            throw SkillportError.parseFailed(reason: "invalid YAML: \(error)")
        }
        let trimmedBody = body.hasPrefix("\n") ? String(body.dropFirst()) : body
        return ParseResult(metadata: metadata, body: trimmedBody)
    }
}
