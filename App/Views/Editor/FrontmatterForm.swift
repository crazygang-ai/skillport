import SwiftUI

struct FrontmatterForm: View {
    @Bindable var state: EditorState

    var body: some View {
        Form {
            // Description 是多段长文（新版 skill 常有上千字），用 axis:.vertical + 弹性行数。
            TextField(
                "Description",
                text: Binding(
                    get: { state.metadata.description ?? "" },
                    set: {
                        state.metadata.description = $0.isEmpty ? nil : $0
                        state.isDirty = true
                    }
                ),
                axis: .vertical
            )
            .lineLimit(3...8)
            TextField(
                "Version",
                text: Binding(
                    get: { state.metadata.version ?? "" },
                    set: {
                        state.metadata.version = $0.isEmpty ? nil : $0
                        state.isDirty = true
                    }
                ))
            TextField(
                "Allowed tools (comma-separated)",
                text: Binding(
                    get: { (state.metadata.allowedTools ?? []).joined(separator: ", ") },
                    set: {
                        let parts = $0.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }.filter { !$0.isEmpty }
                        state.metadata.allowedTools = parts.isEmpty ? nil : parts
                        state.isDirty = true
                    }
                ))
        }
        .padding()
    }
}
