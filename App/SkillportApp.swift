import SwiftUI

@main
struct SkillportApp: App {
    var body: some Scene {
        WindowGroup("Skillport") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    var body: some View {
        VStack {
            Text("Skillport")
                .font(.largeTitle)
            Text("Coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

#Preview {
    Text("Skillport")
}
