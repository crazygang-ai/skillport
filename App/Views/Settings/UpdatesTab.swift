import SwiftUI

struct UpdatesTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(UpdateModel.self) private var update
    @Environment(\.appStrings) private var strings

    var body: some View {
        Form {
            Toggle(
                strings("Automatically check for updates"),
                isOn: autoCheckBinding
            )
            .help(strings("Check for app updates automatically"))
            HStack {
                if let last = update.lastCheck {
                    Text(
                        strings(
                            "Last checked \(last.formatted(date: .abbreviated, time: .shortened))"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(strings("Never checked for updates"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(strings("Check now")) {
                    update.checkNow()
                }
                .help(strings("Check for app updates now"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            update.setAutomaticallyChecksForUpdates(settings.autoCheckUpdates)
        }
    }

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { settings.autoCheckUpdates },
            set: { enabled in
                settings.autoCheckUpdates = enabled
                update.setAutomaticallyChecksForUpdates(enabled)
            }
        )
    }
}
