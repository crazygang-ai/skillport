import SwiftUI

@main
struct SkillportApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup("Skillport", id: "main") {
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
                Button(String(localized: "Import Skill…")) {
                    guard let url = ImportCommand.pickFolder() else { return }
                    Task {
                        do {
                            _ = try await container.skillsModel.installLocal(
                                from: url, installTo: [])
                            container.notificationModel.post(
                                .init(
                                    level: .success,
                                    message: String(
                                        localized: "Imported \(url.lastPathComponent)")))
                        } catch {
                            container.notificationModel.post(
                                .init(
                                    level: .error,
                                    message: String(
                                        localized:
                                            "Import failed: \(error.localizedDescription)")))
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button(String(localized: "Rescan")) {
                    Task { try? await container.skillsModel.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button(String(localized: "Check for Skill Updates")) {}
                    .keyboardShortcut("u", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(container.settingsModel)
                .environment(container.notificationModel)
                .environment(container.updateModel)
        }

        MenuBarExtra("Skillport", systemImage: "cube.box") {
            MenuBarContentView()
                .environment(container.skillsModel)
                .environment(container.updateModel)
        }
        .menuBarExtraStyle(.window)
    }
}
