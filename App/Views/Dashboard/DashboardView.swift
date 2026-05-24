import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.appStrings) private var strings
    @State private var isDropTargeted = false
    @State private var pendingUninstall: Skill?
    @State private var searchText = ""
    @State private var ownershipFilter: SkillOwnershipFilter = .all
    @State private var showingGitHubImport = false

    var body: some View {
        let list = skillsModel.skillsFiltered(
            by: app.currentAgentFilter,
            query: searchText,
            ownership: ownershipFilter
        )
        VStack(spacing: 0) {
            dashboardControls
            if skillsModel.isScanning && skillsModel.skills.isEmpty {
                ProgressView(strings("Scanning…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if list.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                            message: strings(
                                                "Toggle failed: \(error.localizedDescription)")))
                                }
                            }
                        },
                        onOpen: { app.openEditor(for: skill.id) },
                        onUninstall: {
                            pendingUninstall = skill
                        },
                        onCopyPath: {
                            copyPath(skill)
                        },
                        onRevealInFinder: {
                            NSWorkspace.shared.activateFileViewerSelecting([skill.path])
                        },
                        onApplyUpdate: {
                            Task { await applyUpdate(skill) }
                        },
                        onDismissUpdate: { remoteHash in
                            Task { await dismissUpdate(skill, remoteHash: remoteHash) }
                        }
                    )
                }
                .listStyle(.inset)
            }
        }
        .overlay(alignment: .topTrailing) {
            if skillsModel.isScanning && !skillsModel.skills.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .accessibilityLabel(strings("Scanning…"))
            }
        }
        .navigationTitle(
            app.currentAgentFilter?.displayName ?? strings("All Skills")
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingGitHubImport = true
                } label: {
                    Label(strings("Import from GitHub"), systemImage: "globe")
                }
                .help(strings("Import a skill from GitHub"))
                Button {
                    importLocalSkill()
                } label: {
                    Label(strings("Import Skill…"), systemImage: "folder.badge.plus")
                }
                .help(strings("Import a local skill folder"))
            }
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task {
                        try? await skillsModel.refresh(forceAgentSearchPathRefresh: true)
                    }
                } label: {
                    Label(strings("Rescan"), systemImage: "arrow.clockwise")
                }
                .help(strings("Scan local skills and agents"))
                Button {
                    Task { await checkAllUpdates() }
                } label: {
                    Label(strings("Check for Skill Updates"), systemImage: "arrow.down.circle")
                }
                .help(strings("Check all skills for updates"))
            }
        }
        .sheet(isPresented: $showingGitHubImport) {
            GitHubImportSheet()
                .environment(skillsModel)
                .environment(notifications)
        }
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
        .confirmationDialog(
            strings("Delete Skill"),
            isPresented: uninstallDialogBinding,
            presenting: pendingUninstall
        ) { skill in
            Button(strings("Delete"), role: .destructive) {
                Task { await uninstall(skill) }
            }
            .help(strings("Delete this skill"))
            Button(strings("Cancel"), role: .cancel) {}
                .help(strings("Cancel deletion"))
        } message: { skill in
            Text(
                strings(
                    "Delete \(skill.name) everywhere from Skillport? This removes the shared skill, all direct links, and update metadata."
                ))
        }
    }

    private var dashboardControls: some View {
        HStack(spacing: 12) {
            TextField(strings("Search installed skills"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .help(strings("Filter installed skills by name"))

            Picker(strings("Ownership"), selection: $ownershipFilter) {
                Text(strings("All")).tag(SkillOwnershipFilter.all)
                Text(strings("Skillport")).tag(SkillOwnershipFilter.managed)
                Text(strings("External")).tag(SkillOwnershipFilter.external)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .help(strings("Filter skills by ownership"))

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let agent = app.currentAgentFilter, !skillsModel.skills.isEmpty {
            // 有 skills 但没有装到当前 agent
            ContentUnavailableView(
                strings("No skills installed to \(agent.displayName)"),
                systemImage: "cube",
                description: Text(
                    strings(
                        "Clear the agent filter (click title) and toggle \(agent.displayName) on a skill."
                    ))
            )
        } else {
            // 完全没 skills
            ContentUnavailableView(
                strings("No skills yet"),
                systemImage: "sparkles",
                description: Text(
                    strings("Drop a folder with SKILL.md here to import, or use ⌘N."))
            )
        }
    }

    private func importLocalSkill() {
        guard let url = ImportCommand.pickFolder() else { return }
        Task {
            do {
                _ = try await skillsModel.installLocal(from: url, installTo: [])
                notifications.post(
                    .init(
                        level: .success,
                        message: strings("Imported \(url.lastPathComponent)")))
            } catch {
                notifications.post(
                    .init(
                        level: .error,
                        message: strings("Import failed: \(error.localizedDescription)")))
            }
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
                        message: strings("Imported \(url.lastPathComponent)")))
            } catch {
                notifications.post(
                    .init(
                        level: .error,
                        message: strings("Import failed: \(error.localizedDescription)")))
            }
        }
    }

    private func copyPath(_ skill: Skill) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(skill.path.path, forType: .string)
        notifications.post(
            .init(level: .success, message: strings("Copied skill path")))
    }

    private func checkAllUpdates() async {
        do {
            let results = try await skillsModel.checkAllUpdates()
            let available = results.values.filter {
                if case .available = $0 { return true }
                return false
            }.count
            notifications.post(
                .init(
                    level: available > 0 ? .info : .success,
                    message: available > 0
                        ? strings("\(available) skill updates available")
                        : strings("All skills are up to date")
                ))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: strings("Update check failed: \(error.localizedDescription)")
                ))
        }
    }

    private func applyUpdate(_ skill: Skill) async {
        do {
            try await skillsModel.applyUpdate(name: skill.name)
            notifications.post(
                .init(level: .success, message: strings("Updated \(skill.name)")))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: strings("Update failed: \(error.localizedDescription)")))
        }
    }

    private func dismissUpdate(_ skill: Skill, remoteHash: String) async {
        do {
            try await skillsModel.dismissUpdate(name: skill.name, remoteHash: remoteHash)
            notifications.post(
                .init(level: .success, message: strings("Dismissed update for \(skill.name)")))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: strings("Dismiss failed: \(error.localizedDescription)")))
        }
    }

    private func uninstall(_ skill: Skill) async {
        do {
            try await skillsModel.uninstall(name: skill.name)
            pendingUninstall = nil
            notifications.post(
                .init(level: .success, message: strings("Deleted \(skill.name)")))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: strings("Delete failed: \(error.localizedDescription)")))
        }
    }

    private var uninstallDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingUninstall != nil },
            set: { isPresented in
                if !isPresented {
                    pendingUninstall = nil
                }
            }
        )
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
