import SwiftUI

struct NotificationHost: View {
    @Environment(NotificationModel.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                ForEach(notifications.toasts) { toast in
                    ToastView(toast: toast) {
                        notifications.dismiss(id: toast.id)
                    }
                    .task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        notifications.dismiss(id: toast.id)
                    }
                }
            }
            .padding(.bottom, 16)
            .animation(toastAnimation, value: notifications.toasts)
        }
        .allowsHitTesting(!notifications.toasts.isEmpty)
    }

    private var toastAnimation: Animation? {
        reduceMotion
            ? nil
            : .spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.05)
    }
}

private struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void
    @Environment(\.appStrings) private var strings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(toast.message)
            Spacer(minLength: 12)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help(strings("Dismiss notification"))
                .accessibilityLabel(strings("Dismiss notification"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
        .frame(maxWidth: 440)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var icon: String {
        switch toast.level {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch toast.level {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
