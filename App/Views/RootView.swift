import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var requestedSidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DetailArea()
        }
        .navigationSplitViewStyle(.balanced)
        .overlay { NotificationHost() }
    }

    /// Editor 模式下临时隐藏侧边栏；其它模式尊重系统 sidebar toggle 按钮。
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                if case .editor = appModel.section { return .detailOnly }
                return requestedSidebarVisibility
            },
            set: { newValue in
                if case .editor = appModel.section { return }
                requestedSidebarVisibility = newValue
            }
        )
    }
}

private struct DetailArea: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        switch appModel.section {
        case .dashboard:
            DashboardView()
        case .registry:
            RegistryBrowserView()
        case .editor(let id):
            SkillEditorView(skillID: id)
        }
    }
}
