import SwiftUI

struct GeneralTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.appStrings) private var strings

    private let locales: [(String, String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja", "日本語"),
    ]

    var body: some View {
        Form {
            Picker(strings("Language"), selection: localeBinding) {
                ForEach(locales, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            .help(strings("Choose the app language"))
            Text(strings("Language changes apply immediately."))
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
                        message: settings.localized("Language changed.")))
            }
        )
    }
}
