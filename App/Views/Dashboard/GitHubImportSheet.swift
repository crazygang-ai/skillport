import SwiftUI

struct GitHubImportSheet: View {
    @Environment(SkillsModel.self) private var skills
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.dismiss) private var dismiss

    @State private var repoInput = ""
    @State private var skillIdInput = ""
    @State private var selectedAgents: Set<AgentID> = []
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Import from GitHub"))
                .font(.title3)
                .bold()

            Form {
                TextField(
                    String(localized: "Repository"),
                    text: $repoInput,
                    prompt: Text("owner/repo")
                )
                TextField(
                    String(localized: "Skill ID (optional)"),
                    text: $skillIdInput,
                    prompt: Text("subskill")
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Install to agents"))
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
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                Button {
                    Task { await install() }
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "Import"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(repoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInstalling)
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
                .init(level: .success, message: String(localized: "Imported \(installed.name)")))
            dismiss()
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: String(localized: "Import failed: \(error.localizedDescription)")))
        }
    }
}
