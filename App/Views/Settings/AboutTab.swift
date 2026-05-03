import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cube.box")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(
                Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? "Skillport"
            )
            .font(.title2).bold()
            Text(versionString).font(.caption).foregroundStyle(.secondary)
            Link(
                String(localized: "GitHub"),
                destination: URL(string: "https://github.com/crazygang-ai/skillport")!
            )
            .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var versionString: String {
        let marketing =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "?"
        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(marketing) (\(build))"
    }
}
