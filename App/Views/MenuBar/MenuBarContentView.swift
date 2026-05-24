import SwiftUI

struct MenuBarContentView: View {
    @Environment(SkillsModel.self) private var skills
    @Environment(UpdateModel.self) private var update
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appStrings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cube.box").foregroundStyle(.tint)
                Text("Skillport").font(.headline)
                Spacer()
                if update.updateAvailable {
                    Label(strings("Update"), systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            Divider()
            Label(
                strings("\(skills.skills.count) skills installed"),
                systemImage: "list.bullet"
            )
            .font(.caption)

            let updatable = skills.skills.filter {
                if case .available = $0.updateStatus { return true }
                return false
            }.count
            if updatable > 0 {
                Label(
                    strings("\(updatable) skill updates available"),
                    systemImage: "arrow.down.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Divider()
            Button {
                openWindow(id: "main")
            } label: {
                Label(
                    strings("Open Skillport"),
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)
            .help(strings("Open the main Skillport window"))

            Button {
                update.checkNow()
            } label: {
                Label(strings("Check for updates"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(strings("Check for app updates"))

            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label(strings("Quit Skillport"), systemImage: "power")
            }
            .buttonStyle(.plain)
            .help(strings("Quit Skillport"))
        }
        .padding(12)
        .frame(width: 260)
    }
}
