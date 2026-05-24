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

    private var strings: AppStrings {
        AppStrings(localeIdentifier: container.settingsModel.preferredLocale)
    }

    var body: some Scene {
        WindowGroup("Skillport", id: "main") {
            RootView()
                .environment(container.appModel)
                .environment(container.skillsModel)
                .environment(container.notificationModel)
                .environment(container.settingsModel)
                .environment(container.updateModel)
                .environment(container.registryModel)
                .environment(\.locale, strings.locale)
                .environment(\.appStrings, strings)
                .task {
                    lifecycleDelegate.shutdown = { [container] in
                        await container.shutdown()
                    }
                    do {
                        try await container.skillsModel.refresh()
                    } catch {
                        await container.skillsModel.refreshAgents()
                    }
                    await container.skillsModel.startWatching()
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(strings("Import Skill…")) {
                    guard let url = ImportCommand.pickFolder() else { return }
                    Task {
                        do {
                            _ = try await container.skillsModel.installLocal(
                                from: url, installTo: [])
                            container.notificationModel.post(
                                .init(
                                    level: .success,
                                    message: strings("Imported \(url.lastPathComponent)")))
                        } catch {
                            container.notificationModel.post(
                                .init(
                                    level: .error,
                                    message: strings(
                                        "Import failed: \(error.localizedDescription)")))
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .help(strings("Import a local skill folder"))
            }
            CommandGroup(after: .appSettings) {
                Button(strings("Rescan")) {
                    Task { try? await container.skillsModel.refresh(forceAgentSearchPathRefresh: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .help(strings("Scan local skills and agents"))
                Button(strings("Check for Skill Updates")) {
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
                                ? strings("\(available) skill updates available")
                                : strings("All skills are up to date")
                            container.notificationModel.post(.init(level: level, message: msg))
                        } catch {
                            container.notificationModel.post(
                                .init(
                                    level: .error,
                                    message: strings(
                                        "Update check failed: \(error.localizedDescription)")
                                ))
                        }
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
                .help(strings("Check all skills for updates"))
            }
        }

        Settings {
            SettingsView()
                .environment(container.settingsModel)
                .environment(container.notificationModel)
                .environment(container.updateModel)
                .environment(\.locale, strings.locale)
                .environment(\.appStrings, strings)
        }

        MenuBarExtra("Skillport", systemImage: "cube.box") {
            MenuBarContentView()
                .environment(container.skillsModel)
                .environment(container.updateModel)
                .environment(\.locale, strings.locale)
                .environment(\.appStrings, strings)
        }
        .menuBarExtraStyle(.window)
    }
}
