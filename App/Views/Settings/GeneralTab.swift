import SwiftUI

struct GeneralTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(NotificationModel.self) private var notifications

    private let locales: [(String, String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
    ]

    var body: some View {
        Form {
            Picker(String(localized: "Language"), selection: localeBinding) {
                ForEach(locales, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            Text(String(localized: "Restart required for language change to take effect."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var localeBinding: Binding<String> {
        Binding(
            get: { settings.preferredLocale },
            set: { new in
                settings.setPreferredLocale(new)
                notifications.post(
                    .init(
                        level: .info,
                        message: String(localized: "Language changed — please restart Skillport.")))
            }
        )
    }
}
