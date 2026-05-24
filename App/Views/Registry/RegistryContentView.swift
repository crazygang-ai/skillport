import SwiftUI

struct RegistryContentView: View {
    let rendered: RegistryRendered
    let isLoading: Bool
    @Environment(\.appStrings) private var strings

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(strings("Loading…"))
            } else {
                ScrollView {
                    renderedContent
                        .frame(maxWidth: 820, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var renderedContent: some View {
        switch rendered {
        case .empty(let msg):
            Text(msg)
                .foregroundStyle(.secondary)
        case .markdown(let s), .attributed(let s):
            Text(s)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
