import AppKit
import SwiftUI

private final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    var shutdown: (@MainActor @Sendable () async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let shutdown else { return .terminateNow }
        Task { @MainActor in
            await shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct SkillportApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycleDelegate
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
                    lifecycleDelegate.shutdown = { [container] in
                        await container.shutdown()
                    }
                    async let refreshSkills: Void = {
                        try? await container.skillsModel.refresh()
                    }()
                    async let refreshAgents: Void = container.skillsModel.refreshAgents()
                    _ = await (refreshSkills, refreshAgents)
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
                Button(String(localized: "Check for Skill Updates")) {
                    Task {
                        do {
                            let results = try await container.skillsModel.checkAllUpdates()
                            let available = results.values.filter {
                                if case .available = $0 { return true }
                                return false
                            }.count
                            let level: NotificationLevel = available > 0 ? .info : .success
                            let msg =
                                available > 0
                                ? String(localized: "\(available) skill updates available")
                                : String(localized: "All skills are up to date")
                            container.notificationModel.post(.init(level: level, message: msg))
                        } catch {
                            container.notificationModel.post(
                                .init(
                                    level: .error,
                                    message: String(
                                        localized:
                                            "Update check failed: \(error.localizedDescription)")
                                ))
                        }
                    }
                }
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
