import SwiftUI

struct RegistryBrowserView: View {
    @Environment(RegistryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            RegistrySidebar(model: model)
            // Detail panel wired up in T10; placeholder for now so T9 ships clean.
            VStack {
                Spacer()
                Text(String(localized: "Detail panel — coming in T10"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { model.onAppear() }
    }
}
