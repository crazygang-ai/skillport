import SwiftUI

struct NetworkTab: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(NotificationModel.self) private var notifications
    @State private var password: String = ""
    @State private var loadedPassword: Bool = false
    @State private var bypassListText: String = ""
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case bypassList
    }

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
                TextField(
                    String(localized: "Bypass proxy for"),
                    text: $bypassListText,
                    prompt: Text("localhost, 127.0.0.1, *.local"),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .focused($focusedField, equals: .bypassList)
                .onChange(of: bypassListText) { _, newValue in
                    applyBypassList(newValue)
                }
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
                .init(level: .success, message: String(localized: "Proxy password saved")))
        } catch {
            notifications.post(
                .init(
                    level: .error,
                    message: String(localized: "Failed to save password: \(error.localizedDescription)")))
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
