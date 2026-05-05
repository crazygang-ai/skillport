import Foundation
import Observation

@MainActor
@Observable
final class EditorState {
    var metadata = SKILLMetadata()
    var body: String = ""
    var isDirty: Bool = false
    var filePath: URL?
    private var loadedMetadata = SKILLMetadata()
    private var persistedMetadata = SKILLMetadata()

    func load(from url: URL) throws {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let parsed = try SKILLMdParser.parse(raw)
        metadata = parsed.metadata
        loadedMetadata = parsed.metadata
        persistedMetadata = parsed.persistedMetadata
        body = parsed.body
        filePath = url
        isDirty = false
    }

    func save() throws {
        guard let filePath else { return }
        let metadataToPersist = metadataForSaving()
        let serialized = try SKILLMdParser.serialize(metadata: metadataToPersist, body: body)
        let tmp = filePath.appendingPathExtension("tmp")
        try serialized.write(to: tmp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: filePath.path) {
            _ = try FileManager.default.replaceItemAt(filePath, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: filePath)
        }
        loadedMetadata = metadata
        persistedMetadata = metadataToPersist
        isDirty = false
    }

    private func metadataForSaving() -> SKILLMetadata {
        var output = persistedMetadata
        if metadata.name != loadedMetadata.name {
            output.name = metadata.name
        }
        if metadata.description != loadedMetadata.description {
            output.description = metadata.description
        }
        if metadata.version != loadedMetadata.version {
            output.version = metadata.version
        }
        if metadata.allowedTools != loadedMetadata.allowedTools {
            output.allowedTools = metadata.allowedTools
        }
        if metadata.license != loadedMetadata.license {
            output.license = metadata.license
        }
        if metadata.author != loadedMetadata.author {
            output.author = metadata.author
        }
        return output
    }
}
