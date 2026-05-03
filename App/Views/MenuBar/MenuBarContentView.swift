import SwiftUI

struct MenuBarContentView: View {
    @Environment(SkillsModel.self) private var skills
    @Environment(UpdateModel.self) private var update
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cube.box").foregroundStyle(.tint)
                Text("Skillport").font(.headline)
                Spacer()
                if update.updateAvailable {
                    Label(String(localized: "Update"), systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            Divider()
            Label(
                String(localized: "\(skills.skills.count) skills installed"),
                systemImage: "list.bullet"
            )
            .font(.caption)

            let updatable = skills.skills.filter {
                if case .available = $0.updateStatus { return true }
                return false
            }.count
            if updatable > 0 {
                Label(
                    String(localized: "\(updatable) skill updates available"),
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
                    String(localized: "Open Skillport"),
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)

            Button {
                update.checkNow()
            } label: {
                Label(String(localized: "Check for updates"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label(String(localized: "Quit Skillport"), systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
    }
}
