import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel
    @Environment(NotificationModel.self) private var notifications
    @State private var isDropTargeted = false

    var body: some View {
        let list = skillsModel.skillsFiltered(by: app.currentAgentFilter)
        VStack {
            if skillsModel.isScanning {
                ProgressView(String(localized: "Scanning…"))
            } else if list.isEmpty {
                emptyState
            } else {
                List(list) { skill in
                    SkillRow(
                        skill: skill,
                        onToggle: { agent, install in
                            Task {
                                do {
                                    try await skillsModel.toggle(
                                        skillName: skill.name,
                                        agent: agent,
                                        install: install
                                    )
                                } catch {
                                    notifications.post(
                                        .init(
                                            level: .error,
                                            message: String(
                                                localized:
                                                    "Toggle failed: \(error.localizedDescription)")))
                                }
                            }
                        },
                        onOpen: { app.openEditor(for: skill.id) }
                    )
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(
            app.currentAgentFilter?.displayName ?? String(localized: "All Skills")
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { [providers] in await handleDrop(providers: providers) }
            return true
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let agent = app.currentAgentFilter, !skillsModel.skills.isEmpty {
            // 有 skills 但没有装到当前 agent
            ContentUnavailableView(
                String(localized: "No skills installed to \(agent.displayName)"),
                systemImage: "cube",
                description: Text(
                    String(
                        localized:
                            "Clear the agent filter (click title) and toggle \(agent.displayName) on a skill."
                    ))
            )
        } else {
            // 完全没 skills
            ContentUnavailableView(
                String(localized: "No skills yet"),
                systemImage: "sparkles",
                description: Text(
                    String(
                        localized: "Drop a folder with SKILL.md here to import, or use ⌘N."))
            )
        }
    }

    private func handleDrop(providers: [NSItemProvider]) async {
        for provider in providers {
            guard let url = try? await loadFileURL(from: provider) else { continue }
            do {
                _ = try await skillsModel.installLocal(from: url, installTo: [])
                notifications.post(
                    .init(
                        level: .success,
                        message: String(localized: "Imported \(url.lastPathComponent)")))
            } catch {
                notifications.post(
                    .init(
                        level: .error,
                        message: String(
                            localized: "Import failed: \(error.localizedDescription)")))
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            _ = provider.loadObject(ofClass: URL.self) { reading, error in
                if let url = reading {
                    c.resume(returning: url)
                } else {
                    c.resume(throwing: error ?? SkillportError.unexpected("no url"))
                }
            }
        }
    }
}
