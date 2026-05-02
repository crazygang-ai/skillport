import Foundation

/// 纯函数：拆分 SKILL.md 的 frontmatter 与 body；序列化反之。
/// 对应 TS `skill-md-parser.ts`。
public enum SKILLMdParser {
    public struct ParseResult: Sendable {
        public let metadata: SKILLMetadata
        public let body: String
    }

    public static func parse(_ raw: String) throws -> ParseResult {
        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            // 无 frontmatter
            return ParseResult(metadata: SKILLMetadata(), body: raw)
        }
        // 查找关闭行（独占一行的 "---"）
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var closerIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i] == "---" || lines[i] == "---\r" {
                closerIndex = i
                break
            }
        }
        guard let closer = closerIndex else {
            throw SkillportError.parseFailed(file: nil, reason: "unclosed frontmatter")
        }
        let yamlLines = lines[1..<closer]
        let yaml = yamlLines.joined(separator: "\n")
        let bodyLines = lines[(closer + 1)...]
        let body = bodyLines.joined(separator: "\n")
        let metadata: SKILLMetadata
        do {
            metadata = try SKILLMetadata.fromYAML(yaml)
        } catch {
            throw SkillportError.parseFailed(file: nil, reason: "invalid YAML: \(error)")
        }
        // 去掉 body 开头可能的单个换行
        let trimmedBody = body.hasPrefix("\n") ? String(body.dropFirst()) : body
        return ParseResult(metadata: metadata, body: trimmedBody)
    }

    public static func serialize(metadata: SKILLMetadata, body: String) throws -> String {
        let yaml = try metadata.toYAML()
        // 如果 metadata 为空，yaml 可能是 "{}\n" 或空字符串；统一输出空 frontmatter
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return body.hasSuffix("\n") ? body : body + "\n"
        }
        var out = "---\n"
        out += trimmed
        if !trimmed.hasSuffix("\n") { out += "\n" }
        out += "---\n\n"
        out += body
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }
}
