import SwiftUI

struct GitHubImportSheet: View {
    @Environment(SkillsModel.self) private var skills
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appStrings) private var strings

    @State private var repoInput = ""
    @State private var skillIdInput = ""
    @State private var selectedAgents: Set<AgentID> = []
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(strings("Import from GitHub"))
                .font(.title3)
                .bold()

            Form {
                TextField(
                    strings("Repository"),
                    text: $repoInput,
                    prompt: Text("owner/repo")
                )
                .help(strings("Enter a GitHub repository as owner/repo"))
                TextField(
                    strings("Skill ID (optional)"),
                    text: $skillIdInput,
                    prompt: Text("subskill")
                )
                .help(strings("Enter a subskill ID when the repository contains multiple skills"))
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings("Install to agents"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RegistryAgentChipsFlow(
                        agents: skills.agents,
                        selected: selectedAgents
                    ) { id in
                        if selectedAgents.contains(id) {
                            selectedAgents.remove(id)
                        } else {
                            selectedAgents.insert(id)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(strings("Cancel")) {
                    dismiss()
                }
                .help(strings("Cancel import"))
                Button {
                    Task { await install() }
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(strings("Import"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(repoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInstalling)
                .help(strings("Import this GitHub skill"))
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func install() async {
        isInstalling = true
        defer { isInstalling = false }
        do {
            let reference = try GitHubRepoReference.parse(repoInput)
            let installed = try await skills.installGitHub(
                reference: reference,
                skillId: skillIdInput,
                installTo: selectedAgents
            )
            notifications.post(
                .init(level: .success, message: strings("Imported \(installed.name)")))
            dismiss()
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: strings("Import failed: \(error.localizedDescription)")))
        }
    }
}
