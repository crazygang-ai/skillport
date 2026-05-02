import SwiftUI

struct SkillRow: View {
    let skill: Skill
    let onToggle: (AgentID, Bool) -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(skill.name).font(.headline)
                    if let d = skill.frontmatter.description {
                        Text(d).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit SKILL.md")
            }
            AgentsRow(skill: skill, onToggle: onToggle)
        }
        .padding(.vertical, 6)
    }
}

private struct AgentsRow: View {
    let skill: Skill
    let onToggle: (AgentID, Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AgentID.allCases, id: \.self) { id in
                AgentChip(
                    agent: id,
                    installed: skill.installedAgents.contains(id),
                    onToggle: { install in onToggle(id, install) }
                )
            }
        }
    }
}

private struct AgentChip: View {
    let agent: AgentID
    let installed: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!installed)
        } label: {
            Text(agent.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(installed ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(installed ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(installed ? "Uninstall from \(agent.displayName)" : "Install to \(agent.displayName)")
    }
}
