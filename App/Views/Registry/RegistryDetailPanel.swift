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
            let installed = skills.agents.filter(\.isInstalled)
            RegistryAgentChipsFlow(
                agents: installed,
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
                        skill.isSingleSkillRepo
                            ? String(localized: "Install")
                            : String(localized: "Multi-skill repo — use CLI above")
                    )
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .disabled(!skill.isSingleSkillRepo || model.selectedAgentsForInstall.isEmpty)
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
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        return layout(subviews: subviews, width: width).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (sv, rect) in zip(subviews, result.rects) {
            sv.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                proposal: .init(rect.size)
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (rects: [CGRect], size: CGSize) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rects: [CGRect] = []
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rects.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return (rects, CGSize(width: width, height: y + rowHeight))
    }
}
