import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(SkillsModel.self) private var skillsModel

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            // Section switcher — lives outside the selection List so its taps are not swallowed.
            Picker("", selection: sectionBinding) {
                Label(String(localized: "Dashboard"), systemImage: "square.grid.2x2")
                    .tag(SectionTag.dashboard)
                Label(String(localized: "Registry"), systemImage: "books.vertical")
                    .tag(SectionTag.registry)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            // Agent filter list
            List(
                selection: Binding(
                    get: { app.currentAgentFilter },
                    set: { app.selectAgent($0) }
                )
            ) {
                Section(String(localized: "Filter by agent")) {
                    ForEach(skillsModel.agents, id: \.id) { agent in
                        NavigationLink(value: agent.id) {
                            Label(agent.id.displayName, systemImage: "cube")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Section binding

    private enum SectionTag: Hashable {
        case dashboard
        case registry
    }

    private var sectionBinding: Binding<SectionTag> {
        Binding(
            get: {
                switch app.section {
                case .registry: return .registry
                default: return .dashboard
                }
            },
            set: { tag in
                switch tag {
                case .dashboard: app.setSection(.dashboard)
                case .registry: app.setSection(.registry)
                }
            }
        )
    }
}
