import Foundation
import Observation

@MainActor
@Observable
final class EditorState {
    var metadata = SKILLMetadata()
    var body: String = ""
    var isDirty: Bool = false
    var filePath: URL?

    func load(from url: URL) throws {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let parsed = try SKILLMdParser.parse(raw)
        metadata = parsed.metadata
        body = parsed.body
        filePath = url
        isDirty = false
    }

    func save() throws {
        guard let filePath else { return }
        let serialized = try SKILLMdParser.serialize(metadata: metadata, body: body)
        let tmp = filePath.appendingPathExtension("tmp")
        try serialized.write(to: tmp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: filePath.path) {
            _ = try FileManager.default.replaceItemAt(filePath, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: filePath)
        }
        isDirty = false
    }
}
