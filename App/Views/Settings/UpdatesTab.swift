import SwiftUI

struct UpdatesTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(UpdateModel.self) private var update

    var body: some View {
        Form {
            Toggle(
                String(localized: "Automatically check for updates"),
                isOn: autoCheckBinding
            )
            HStack {
                if let last = update.lastCheck {
                    Text(
                        String(
                            localized:
                                "Last checked \(last.formatted(date: .abbreviated, time: .shortened))"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "Never checked for updates"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Check now")) {
                    update.checkNow()
                }
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
