import SwiftUI

struct SettingsView: View {
    @Environment(\.appStrings) private var strings

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label(strings("General"), systemImage: "gearshape")
                        .help(strings("Open general settings"))
                }
            NetworkTab()
                .tabItem {
                    Label(strings("Network"), systemImage: "network")
                        .help(strings("Open network settings"))
                }
            UpdatesTab()
                .tabItem {
                    Label(
                        strings("Updates"),
                        systemImage: "arrow.triangle.2.circlepath")
                        .help(strings("Open update settings"))
                }
            AboutTab()
                .tabItem {
                    Label(strings("About"), systemImage: "info.circle")
                        .help(strings("Open app information"))
                }
        }
        .frame(width: 520, height: 380)
    }
}
