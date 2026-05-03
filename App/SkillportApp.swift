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
                .environment(container.registryModel)
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
                Button("Import Skill…") {
                    guard let url = ImportCommand.pickFolder() else { return }
                    Task {
                        do {
                            _ = try await container.skillsModel.installLocal(
                                from: url, installTo: [])
                            container.notificationModel.post(
                                .init(
                                    level: .success,
                                    message: "Imported \(url.lastPathComponent)"))
                        } catch {
                            container.notificationModel.post(
                                .init(
                                    level: .error,
                                    message: "Import failed: \(error)"))
                        }
                    }
                }
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
