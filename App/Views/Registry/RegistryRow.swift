import SwiftUI

struct RegistryRow: View {
    let skill: RegistrySkill
    @Environment(\.appStrings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(skill.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle")
                    Text(formatInstalls(skill.installs))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(skill.source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(skill.name), \(skill.source), \(strings("\(skill.installs) installs"))"
        )
    }

    private func formatInstalls(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }
}
