import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SkillsModel.self) private var skillsModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DetailArea()
        }
        .overlay { NotificationHost() }
    }
}

private struct DetailArea: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        switch appModel.section {
        case .dashboard:
            DashboardView()
        case .registry:
            Text("Registry — 接在下一份 plan 的 M5")
                .foregroundStyle(.secondary)
        case .editor(let id):
            SkillEditorView(skillID: id)
        }
    }
}
