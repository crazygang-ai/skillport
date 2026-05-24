import SwiftUI

struct RegistryRow: View {
    let skill: RegistrySkill
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(skill.name).font(.body).lineLimit(1)
                Spacer()
                Label(formatInstalls(skill.installs), systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(skill.source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isSelected)
    }

    private func formatInstalls(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }
}
