import SwiftUI

struct NetworkTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(NotificationModel.self) private var notifications
    @State private var password: String = ""
    @State private var loadedPassword: Bool = false

    var body: some View {
        Form {
            Toggle(String(localized: "Enable proxy"), isOn: proxyEnabledBinding)

            if settings.proxy.enabled {
                Picker(String(localized: "Type"), selection: proxyKindBinding) {
                    Text("HTTPS").tag(ProxyConfig.Kind.https)
                    Text("SOCKS5").tag(ProxyConfig.Kind.socks5)
                }
                TextField(String(localized: "Host"), text: proxyHostBinding)
                TextField(
                    String(localized: "Port"), value: proxyPortBinding,
                    formatter: NumberFormatter()
                )
                TextField(String(localized: "Username (optional)"), text: proxyUsernameBinding)
                SecureField(
                    String(localized: "Password (stored in Keychain)"), text: $password
                )
                Button(String(localized: "Save password")) {
                    Task { await savePassword() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            if !loadedPassword {
                loadedPassword = true
                password = (try? await settings.readProxyPassword()) ?? ""
            }
        }
    }

    private func savePassword() async {
        do {
            if password.isEmpty {
                try await settings.clearProxyPassword()
            } else {
                try await settings.setProxyPassword(password)
            }
            notifications.post(
                .init(level: .success, message: String(localized: "Proxy password saved")))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: String(localized: "Failed to save password: \(error.localizedDescription)")))
        }
    }

    private var proxyEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.proxy.enabled },
            set: { new in
                var p = settings.proxy
                p.enabled = new
                Task { await settings.apply(proxy: p) }
            }
        )
    }
    private var proxyKindBinding: Binding<ProxyConfig.Kind> {
        Binding(
            get: { settings.proxy.kind },
            set: { new in
                var p = settings.proxy
                p.kind = new
                Task { await settings.apply(proxy: p) }
            }
        )
    }
    private var proxyHostBinding: Binding<String> {
        Binding(
            get: { settings.proxy.host },
            set: { new in
                var p = settings.proxy
                p.host = new
                Task { await settings.apply(proxy: p) }
            }
        )
    }
    private var proxyPortBinding: Binding<Int> {
        Binding(
            get: { settings.proxy.port },
            set: { new in
                var p = settings.proxy
                p.port = new
                Task { await settings.apply(proxy: p) }
            }
        )
    }
    private var proxyUsernameBinding: Binding<String> {
        Binding(
            get: { settings.proxy.username ?? "" },
            set: { new in
                var p = settings.proxy
                p.username = new.isEmpty ? nil : new
                Task { await settings.apply(proxy: p) }
            }
        )
    }
}
