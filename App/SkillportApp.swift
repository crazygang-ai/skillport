import SwiftUI

@main
struct SkillportApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup("Skillport") {
            RootView()
                .environment(container.appModel)
                .environment(container.skillsModel)
                .environment(container.notificationModel)
                .environment(container.settingsModel)
                .environment(container.updateModel)
                .task {
                    try? await container.skillsModel.refresh()
                    await container.skillsModel.startWatching()
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Skill…") {}  // 接在 Task 48
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Rescan") {
                    Task { try? await container.skillsModel.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Check for Skill Updates") {}  // 接在后续 milestone
                    .keyboardShortcut("u", modifiers: .command)
            }
        }

        Settings {
            Text("Settings — 下一里程碑实现")
                .padding()
                .frame(minWidth: 400, minHeight: 200)
        }
    }
}
