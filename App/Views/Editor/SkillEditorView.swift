import CodeEditor
import SwiftUI

struct SkillEditorView: View {
    let skillID: SkillIdentity?

    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel
    @Environment(NotificationModel.self) private var notifications
    @State private var state = EditorState()
    @State private var source: String = ""

    var body: some View {
        HSplitView {
            VStack {
                FrontmatterForm(state: state)
                Divider()
                CodeEditor(source: $source, language: .markdown, theme: .default)
                    .onChange(of: source) { _, new in
                        state.body = new
                        state.isDirty = true
                    }
            }
            .frame(minWidth: 320)
            MarkdownPreview(source: source)
                .frame(minWidth: 320)
        }
        .navigationTitle(state.filePath?.lastPathComponent ?? "Editor")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    app.setSection(.dashboard)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Back to Dashboard")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    do {
                        try state.save()
                        notifications.post(.init(level: .success, message: "Saved."))
                    } catch {
                        notifications.post(
                            .init(level: .error, message: "Save failed: \(error)"))
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!state.isDirty)
            }
        }
        .task(id: skillID) {
            if let skillID, let skill = skillsModel.skills.first(where: { $0.id == skillID }) {
                do {
                    try state.load(from: skill.path.appendingPathComponent("SKILL.md"))
                    source = state.body
                } catch {
                    notifications.post(.init(level: .error, message: "Load failed: \(error)"))
                }
            }
        }
    }
}
