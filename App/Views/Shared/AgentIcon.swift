import AppKit
import SwiftUI

struct AgentIcon: View {
    let identity: AgentVisualIdentity
    let isInstalled: Bool
    let size: CGFloat

    init(agentID: AgentID, isInstalled: Bool = true, size: CGFloat = 18) {
        self.identity = agentID.visualIdentity
        self.isInstalled = isInstalled
        self.size = size
    }

    var body: some View {
        ZStack {
            if let image = officialImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(iconPadding)
                    .saturation(isInstalled ? 1 : 0)
                    .opacity(isInstalled ? 1 : 0.45)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var officialImage: NSImage? {
        let url =
            Bundle.main.url(
                forResource: identity.assetName,
                withExtension: "png",
                subdirectory: "AgentIcons"
            ) ?? Bundle.main.url(forResource: identity.assetName, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.14))
            .overlay(
                Text(identity.fallbackInitials)
                    .font(.system(size: max(8, size * 0.42), weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }

    private var cornerRadius: CGFloat {
        min(6, size * 0.28)
    }

    private var iconPadding: CGFloat {
        max(1, size * 0.08)
    }
}
