import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            NetworkTab()
                .tabItem { Label(String(localized: "Network"), systemImage: "network") }
            UpdatesTab()
                .tabItem {
                    Label(
                        String(localized: "Updates"),
                        systemImage: "arrow.triangle.2.circlepath")
                }
            AboutTab()
                .tabItem { Label(String(localized: "About"), systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }
}
