import SwiftUI

struct RegistryBrowserView: View {
    @Environment(RegistryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            RegistrySidebar(model: model)
            RegistryDetailPanel(model: model)
        }
        .onAppear { model.onAppear() }
    }
}
