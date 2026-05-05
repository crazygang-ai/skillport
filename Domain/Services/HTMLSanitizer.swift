import Foundation
import SwiftSoup

public struct HTMLSanitizer {
    private static let allowedTags: Set<String> = [
        "p", "a", "ul", "ol", "li", "pre", "code", "blockquote",
        "strong", "em", "h1", "h2", "h3", "h4", "h5", "h6",
        "img", "hr", "br", "table", "thead", "tbody", "tr", "th", "td",
    ]
    private static let allowedAttrs: Set<String> = [
        "href", "src", "alt", "title", "target", "rel",
    ]
    private static let urlAttrs: Set<String> = ["href", "src"]
    private static let safeHrefProtocols: Set<String> = ["http", "https", "mailto", "tel"]
    private static let safeSrcProtocols: Set<String> = ["http", "https"]

    public init() {}

    public func sanitize(_ html: String) throws -> String {
        let doc: Document
        do {
            doc = try SwiftSoup.parseBodyFragment(html)
        } catch {
            throw SkillportError.parseFailed(file: nil, reason: "swiftsoup parse: \(error)")
        }
        guard let body = doc.body() else {
            return ""
        }
        do {
            // 第一趟: 移除危险根节点 (script / style / iframe / object / embed)
            let dangerous = ["script", "style", "iframe", "object", "embed"]
            for tag in dangerous {
                for el in try body.select(tag).array() {
                    try el.remove()
                }
            }
            // 第二趟: 其余不在 allowlist 的标签保留内容, 去掉标签本身
            // Note: 必须自底向上遍历, 不然 unwrap 后子元素会被重新访问
            let elements = try body.getAllElements().array().reversed()
            for el in elements {
                let tag = el.tagName().lowercased()
                if tag == "body" || tag == "html" { continue }
                if !Self.allowedTags.contains(tag) {
                    try el.unwrap()
                    continue
                }
                // 清属性
                let keys = el.getAttributes()?.asList().map { $0.getKey() } ?? []
                for key in keys {
                    let lowerKey = key.lowercased()
                    if !Self.allowedAttrs.contains(lowerKey) {
                        try el.removeAttr(key)
                        continue
                    }
                    if Self.urlAttrs.contains(lowerKey) {
                        let val = try el.attr(key)
                        if !Self.isSafeURL(val, attr: lowerKey) {
                            try el.removeAttr(key)
                        }
                    }
                }
                if tag == "a", el.hasAttr("href") {
                    try el.attr("rel", "noopener noreferrer")
                }
                if tag == "img", !el.hasAttr("alt") {
                    try el.attr("alt", "")
                }
            }
            return try body.html()
        } catch {
            throw SkillportError.parseFailed(file: nil, reason: "sanitize: \(error)")
        }
    }

    private static func isSafeURL(_ value: String, attr: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("//") { return false }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("/")
            || trimmed.hasPrefix("./") || trimmed.hasPrefix("../")
        {
            return true
        }
        guard let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        switch attr {
        case "href":
            return safeHrefProtocols.contains(scheme)
        case "src":
            return safeSrcProtocols.contains(scheme)
        default:
            return false
        }
    }
}
