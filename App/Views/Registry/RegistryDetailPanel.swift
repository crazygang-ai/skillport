import SwiftUI

struct RegistryDetailPanel: View {
    @Bindable var model: RegistryModel
    @Environment(SkillsModel.self) private var skills
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.appStrings) private var strings

    var body: some View {
        Group {
            if let id = model.selectedID,
                let skill = model.skills.first(where: { $0.id == id })
            {
                VStack(alignment: .leading, spacing: 0) {
                    header(skill)
                    installCommandBar(skill)
                    Divider()
                    RegistryContentView(
                        rendered: model.rendered, isLoading: model.isContentLoading
                    )
                    .layoutPriority(1)
                    Divider()
                    agentSelector(skill)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack {
                    Spacer()
                    Text(strings("Select a skill to see details"))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ skill: RegistrySkill) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.name)
                .font(.title2)
                .bold()
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 12) {
                Label(strings("\(skill.installs) installs"), systemImage: "arrow.down.circle")
                if let url = URL(string: "https://skills.sh/\(skill.id)") {
                    Link("skills.sh", destination: url)
                        .help(strings("Open this skill on skills.sh"))
                }
                if let url = URL(string: "https://github.com/\(skill.source)") {
                    Link(skill.source, destination: url)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(strings("Open source repository"))
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
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
                .textSelection(.enabled)
                .help(strings("Install command"))
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(skill.installCommand, forType: .string)
                notifications.post(
                    .init(level: .success, message: strings("Copied install command")))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help(strings("Copy install command"))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Agent selector + install

    @ViewBuilder
    private func agentSelector(_ skill: RegistrySkill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings("Install to agents"))
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
                            ? strings("Install to Skillport")
                            : strings("Install")
                    )
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .help(installButtonHelp)
        }
        .padding()
    }

    private var installButtonHelp: String {
        model.selectedAgentsForInstall.isEmpty
            ? strings("Install into Skillport")
            : strings("Install to selected agents")
    }

    private func handleInstall(_ skill: RegistrySkill) async {
        let result = await model.installSelected()
        switch result {
        case .success(let installed):
            notifications.post(
                .init(
                    level: .success,
                    message: strings("Installed \(installed.name)")))
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
    @Environment(\.appStrings) private var strings

    var body: some View {
        FlowLayout {
            ForEach(agents, id: \.id) { agent in
                Button {
                    toggle(agent.id)
                } label: {
                    HStack(spacing: 5) {
                        AgentIcon(agentID: agent.id, isInstalled: agent.isInstalled, size: 16)
                        Text(agent.id.displayName)
                            .font(.caption)
                    }
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
                .help(helpText(for: agent))
            }
        }
    }

    private func helpText(for agent: Agent) -> String {
        if !agent.isInstalled {
            return strings("\(agent.id.displayName) is not detected on this Mac.")
        }
        if selected.contains(agent.id) {
            return strings("Remove \(agent.id.displayName) from install targets")
        }
        return strings("Install to \(agent.id.displayName)")
    }
}
