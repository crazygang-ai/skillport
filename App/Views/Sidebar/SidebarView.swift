import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel
    @Environment(\.appStrings) private var strings

    var body: some View {
        List(selection: selectionBinding) {
            Section(strings("Views")) {
                Label(strings("Dashboard"), systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.dashboard)
                    .help(strings("Show installed skills"))
                Label(strings("Registry"), systemImage: "books.vertical")
                    .tag(SidebarSelection.registry)
                    .help(strings("Browse the skill registry"))
            }

            Section {
                if skillsModel.hasDetectedAgents {
                    ForEach(skillsModel.agents, id: \.id) { agent in
                        SidebarAgentRow(
                            agent: agent,
                            count: skillsModel.skillCount(for: agent.id)
                        )
                        .tag(SidebarSelection.agent(agent.id))
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text(strings("Filter by agent"))
                    if skillsModel.isDetectingAgents || !skillsModel.hasDetectedAgents {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(strings("Detecting agents..."))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Unified sidebar selection

    private enum SidebarSelection: Hashable {
        case dashboard
        case registry
        case agent(AgentID)
    }

    private var selectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: {
                switch app.section {
                case .registry:
                    return .registry
                case .editor:
                    // editor 时 sidebar 仍高亮 Dashboard (editor 是从 Dashboard 点进去的)
                    if let id = app.currentAgentFilter { return .agent(id) }
                    return .dashboard
                case .dashboard:
                    if let id = app.currentAgentFilter { return .agent(id) }
                    return .dashboard
                }
            },
            set: { new in
                guard let new else { return }
                switch new {
                case .dashboard:
                    app.setSection(.dashboard)
                    app.selectAgent(nil)
                case .registry:
                    app.setSection(.registry)
                    app.selectAgent(nil)
                case .agent(let id):
                    app.setSection(.dashboard)
                    app.selectAgent(id)
                }
            }
        )
    }
}

private struct SidebarAgentRow: View {
    let agent: Agent
    let count: Int
    @Environment(\.appStrings) private var strings

    var body: some View {
        HStack(spacing: 10) {
            AgentIcon(agentID: agent.id, isInstalled: agent.isInstalled, size: 18)
            Text(agent.id.displayName)
                .foregroundStyle(agent.isInstalled ? Color.primary : Color.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(agent.isInstalled ? 1 : 0.55)
        .help(helpText)
    }

    private var helpText: String {
        if agent.isInstalled {
            return strings("Show skills for \(agent.id.displayName)")
        }
        return strings("\(agent.id.displayName) is not detected on this Mac.")
    }
}
