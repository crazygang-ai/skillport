import SwiftUI

struct NetworkTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.appStrings) private var strings
    @State private var password: String = ""
    @State private var loadedPassword: Bool = false
    @State private var bypassListText: String = ""
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case bypassList
    }

    var body: some View {
        Form {
            Toggle(strings("Enable proxy"), isOn: proxyEnabledBinding)
                .help(strings("Enable the network proxy"))

            if settings.proxy.enabled {
                Picker(strings("Type"), selection: proxyKindBinding) {
                    Text("HTTPS").tag(ProxyConfig.Kind.https)
                    Text("SOCKS5").tag(ProxyConfig.Kind.socks5)
                }
                .help(strings("Choose proxy type"))
                TextField(strings("Host"), text: proxyHostBinding)
                    .help(strings("Proxy host name or IP address"))
                TextField(
                    strings("Port"), value: proxyPortBinding,
                    formatter: NumberFormatter()
                )
                .help(strings("Proxy port number"))
                TextField(strings("Username (optional)"), text: proxyUsernameBinding)
                    .help(strings("Optional proxy username"))
                SecureField(
                    strings("Password (stored in Keychain)"), text: $password
                )
                .help(strings("Proxy password stored in Keychain"))
                Button(strings("Save password")) {
                    Task { await savePassword() }
                }
                .help(strings("Save proxy password to Keychain"))
                TextField(
                    strings("Bypass proxy for"),
                    text: $bypassListText,
                    prompt: Text("localhost, 127.0.0.1, *.local"),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .focused($focusedField, equals: .bypassList)
                .onChange(of: bypassListText) { _, newValue in
                    applyBypassList(newValue)
                }
                .help(strings("Comma-separated hosts that bypass the proxy"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            syncBypassListText(force: true)
        }
        .onChange(of: settings.proxy) {
            syncBypassListText(force: false)
        }
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
                .init(level: .success, message: strings("Proxy password saved")))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: strings("Failed to save password: \(error.localizedDescription)")))
        }
    }

    private func applyBypassList(_ raw: String) {
        let entries = ProxyBypassListFormatter.parse(raw)
        let nextList: [String]? = entries.isEmpty ? nil : entries
        guard settings.proxy.bypassList != nextList else { return }
        var p = settings.proxy
        p.bypassList = nextList
        Task { await settings.apply(proxy: p) }
    }

    private func syncBypassListText(force: Bool) {
        guard force || focusedField != .bypassList else { return }
        let rendered = ProxyBypassListFormatter.string(from: settings.proxy.bypassList)
        if bypassListText != rendered {
            bypassListText = rendered
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
