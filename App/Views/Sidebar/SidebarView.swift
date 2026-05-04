import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel

    var body: some View {
        List(selection: selectionBinding) {
            Section(String(localized: "Views")) {
                Label(String(localized: "Dashboard"), systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.dashboard)
                Label(String(localized: "Registry"), systemImage: "books.vertical")
                    .tag(SidebarSelection.registry)
            }

            Section(String(localized: "Filter by agent")) {
                ForEach(skillsModel.agents.filter(\.isInstalled), id: \.id) { agent in
                    Label(agent.id.displayName, systemImage: "cube")
                        .tag(SidebarSelection.agent(agent.id))
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
