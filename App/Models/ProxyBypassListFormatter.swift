import Foundation

enum ProxyBypassListFormatter {
    static func parse(_ raw: String) -> [String] {
        raw.split { ch in
            ch == "," || ch == "\n" || ch == "\r"
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static func string(from entries: [String]?) -> String {
        (entries ?? []).joined(separator: ", ")
    }
}
