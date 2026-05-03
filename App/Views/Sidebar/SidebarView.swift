import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel

    var body: some View {
        @Bindable var app = app
        List(
            selection: Binding(
                get: { app.currentAgentFilter },
                set: { app.selectAgent($0) }
            )
        ) {
            Section(String(localized: "Views")) {
                Button {
                    app.setSection(.dashboard)
                } label: {
                    Label(String(localized: "Dashboard"), systemImage: "square.grid.2x2")
                }
                Button {
                    app.setSection(.registry)
                } label: {
                    Label(String(localized: "Registry"), systemImage: "books.vertical")
                }
            }
            .buttonStyle(.plain)

            Section(String(localized: "Filter by agent")) {
                ForEach(skillsModel.agents, id: \.id) { agent in
                    NavigationLink(value: agent.id) {
                        HStack {
                            Label(agent.id.displayName, systemImage: "cube")
                            Spacer()
                            Text("\(count(for: agent.id))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func count(for id: AgentID) -> Int {
        skillsModel.skillsFiltered(by: id).count
    }
}
