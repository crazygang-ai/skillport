import SwiftUI

struct RegistryDetailPanel: View {
    @Bindable var model: RegistryModel
    @Environment(SkillsModel.self) private var skills
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                ContentUnavailableView(
                    strings("Select a skill"),
                    systemImage: "books.vertical",
                    description: Text(strings("Choose a registry result to preview documentation and install it."))
                )
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
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
                .help(strings("Install command"))
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(skill.installCommand, forType: .string)
                notifications.post(
                    .init(level: .success, message: strings("Copied install command")))
            } label: {
                Label(strings("Copy install command"), systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings("Copy install command"))
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
                selected: model.selectedAgentsForInstall,
                isDisabled: model.isInstalling
            ) { id in
                withMotion {
                    model.toggleAgentForInstall(id)
                }
            }
            Button {
                Task { await handleInstall(skill) }
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    if model.isInstallingSelectedSkill {
                        ProgressView()
                            .controlSize(.small)
                        Text(strings("Installing…"))
                    } else {
                        Image(systemName: "tray.and.arrow.down")
                            .imageScale(.small)
                        Text(
                            model.selectedAgentsForInstall.isEmpty
                                ? strings("Install to Skillport")
                                : strings("Install")
                        )
                    }
                    Spacer()
                }
                .frame(minHeight: 22)
                .padding(.vertical, 6)
                .contentTransition(.opacity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isInstalling)
            .help(installButtonHelp)
            .animation(microAnimation, value: model.isInstallingSelectedSkill)
        }
        .padding()
    }

    private var installButtonHelp: String {
        if model.isInstalling {
            return strings("Installing…")
        }
        return model.selectedAgentsForInstall.isEmpty
            ? strings("Install into Skillport")
            : strings("Install to selected agents")
    }

    private var microAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }

    private func withMotion(_ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.snappy(duration: 0.18), action)
        }
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
    var isDisabled = false
    let toggle: (AgentID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appStrings) private var strings

    var body: some View {
        FlowLayout {
            ForEach(agents, id: \.id) { agent in
                Button {
                    toggle(agent.id)
                } label: {
                    let isSelected = selected.contains(agent.id)
                    HStack(spacing: 5) {
                        AgentIcon(agentID: agent.id, isInstalled: agent.isInstalled, size: 16)
                        Text(agent.id.displayName)
                            .font(.caption)
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 10)
                            .opacity(isSelected ? 1 : 0)
                            .scaleEffect(isSelected ? 1 : 0.7)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : Color.secondary.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                isSelected
                                    ? Color.accentColor.opacity(0.55)
                                    : Color.secondary.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled || !agent.isInstalled)
                .opacity(agent.isInstalled ? (isDisabled ? 0.7 : 1) : 0.48)
                .help(helpText(for: agent))
                .accessibilityLabel(accessibilityLabel(for: agent))
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.16),
                    value: selected.contains(agent.id)
                )
            }
        }
    }

    private func helpText(for agent: Agent) -> String {
        if isDisabled {
            return strings("Installing…")
        }
        if !agent.isInstalled {
            return strings("\(agent.id.displayName) is not detected on this Mac.")
        }
        if selected.contains(agent.id) {
            return strings("Remove \(agent.id.displayName) from install targets")
        }
        return strings("Install to \(agent.id.displayName)")
    }

    private func accessibilityLabel(for agent: Agent) -> String {
        let state = selected.contains(agent.id) ? strings("Selected") : strings("Not selected")
        return "\(agent.id.displayName), \(state)"
    }
}
