import SwiftUI

struct RegistryContentView: View {
    let rendered: RegistryRendered
    let isLoading: Bool

    var body: some View {
        ScrollView {
            Group {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }.padding()
                } else {
                    switch rendered {
                    case .empty(let msg):
                        Text(msg)
                            .foregroundStyle(.secondary)
                            .padding()
                    case .markdown(let s), .attributed(let s):
                        Text(s)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
