import Foundation

/// 纯函数：拆分 SKILL.md 的 frontmatter 与 body；序列化反之。
public enum SKILLMdParser {
    public struct ParseResult: Sendable {
        public let metadata: SKILLMetadata
        public let body: String
    }

    public static func parse(_ raw: String) throws -> ParseResult {
        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            // 无 frontmatter — 从 body 的第一个 `# Heading` + 首段 fallback 提取 name/description。
            return ParseResult(metadata: metadataFromMarkdown(raw), body: raw)
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
        var metadata: SKILLMetadata
        do {
            metadata = try SKILLMetadata.fromYAML(yaml)
        } catch {
            throw SkillportError.parseFailed(file: nil, reason: "invalid YAML: \(error)")
        }
        // 若 frontmatter 未写 name/description，从 markdown body fallback 补齐。
        if metadata.name == nil || metadata.description == nil {
            let bodyFallback = metadataFromMarkdown(body)
            if metadata.name == nil { metadata.name = bodyFallback.name }
            if metadata.description == nil { metadata.description = bodyFallback.description }
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

    /// 从纯 markdown（无 frontmatter）提取 name 与 description：
    /// - name = 第一个 `# <title>` 行的 `<title>`。
    /// - description = 紧随其后的第一段非空文本（单段，合并为一行）。
    private static func metadataFromMarkdown(_ raw: String) -> SKILLMetadata {
        var name: String? = nil
        var description: String? = nil
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if name == nil, line.hasPrefix("# ") {
                name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                i += 1
                // 跳空行
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
                // 收集首段（到下一个空行或标题为止）
                var paragraph: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    let trimmed = l.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { break }
                    if trimmed.hasPrefix("#") { break }
                    paragraph.append(trimmed)
                    i += 1
                }
                if !paragraph.isEmpty {
                    description = paragraph.joined(separator: " ")
                }
                break
            }
            i += 1
        }
        return SKILLMetadata(name: name, description: description)
    }
}
