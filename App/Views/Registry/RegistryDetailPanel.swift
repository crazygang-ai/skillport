import SwiftUI

struct RegistryDetailPanel: View {
    @Bindable var model: RegistryModel
    @Environment(SkillsModel.self) private var skills
    @Environment(NotificationModel.self) private var notifications

    var body: some View {
        if let id = model.selectedID,
            let skill = model.skills.first(where: { $0.id == id })
        {
            VStack(alignment: .leading, spacing: 0) {
                header(skill)
                installCommandBar(skill)
                Divider()
                RegistryContentView(
                    rendered: model.rendered, isLoading: model.isContentLoading)
                Divider()
                agentSelector(skill)
            }
        } else {
            VStack {
                Spacer()
                Text(String(localized: "Select a skill to see details"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ skill: RegistrySkill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.name).font(.title2).bold()
            HStack(spacing: 12) {
                Label("\(skill.installs) installs", systemImage: "arrow.down.circle")
                if let url = URL(string: "https://skills.sh/\(skill.id)") {
                    Link("skills.sh", destination: url)
                }
                if let url = URL(string: "https://github.com/\(skill.source)") {
                    Link(skill.source, destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Install command bar

    @ViewBuilder
    private func installCommandBar(_ skill: RegistrySkill) -> some View {
        HStack(spacing: 8) {
            Text(skill.installCommand)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
                .textSelection(.enabled)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(skill.installCommand, forType: .string)
                notifications.post(
                    .init(level: .success, message: String(localized: "Copied install command")))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Agent selector + install

    @ViewBuilder
    private func agentSelector(_ skill: RegistrySkill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Install to agents"))
                .font(.caption)
                .foregroundStyle(.secondary)
            RegistryAgentChipsFlow(
                agents: skills.agents,
                selected: model.selectedAgentsForInstall
            ) { id in
                model.toggleAgentForInstall(id)
            }
            Button {
                Task { await handleInstall(skill) }
            } label: {
                HStack {
                    Spacer()
                    Text(
                        model.selectedAgentsForInstall.isEmpty
                            ? String(localized: "Install to Skillport")
                            : String(localized: "Install")
                    )
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func handleInstall(_ skill: RegistrySkill) async {
        let result = await model.installSelected()
        switch result {
        case .success(let installed):
            notifications.post(
                .init(
                    level: .success,
                    message: String(localized: "Installed \(installed.name)")))
        case .failure(let error):
            notifications.post(
                .init(level: .error, message: String(describing: error)))
        }
    }
}

/// Wrapping flow for the agent chip row — Swift 6 Layout protocol.
struct RegistryAgentChipsFlow: View {
    let agents: [Agent]
    let selected: Set<AgentID>
    let toggle: (AgentID) -> Void

    var body: some View {
        FlowLayout {
            ForEach(agents, id: \.id) { agent in
                Button {
                    toggle(agent.id)
                } label: {
                    Text(agent.id.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            selected.contains(agent.id)
                                ? Color.accentColor.opacity(0.3)
                                : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!agent.isInstalled)
                .opacity(agent.isInstalled ? 1 : 0.48)
                .help(
                    agent.isInstalled
                        ? "Install to \(agent.id.displayName)"
                        : "\(agent.id.displayName) is not detected on this Mac."
                )
            }
        }
    }
}
