import SwiftUI

struct RegistryBrowserView: View {
    @Environment(RegistryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            RegistrySidebar(model: model)
                .frame(width: 320)
            RegistryDetailPanel(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.onAppear() }
    }
}
