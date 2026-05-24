import SwiftUI

struct SkillRow: View {
    let skill: Skill
    let onToggle: (AgentID, Bool) -> Void
    let onOpen: () -> Void
    let onUninstall: () -> Void
    let onApplyUpdate: () -> Void
    let onDismissUpdate: (String) -> Void

    @Environment(SkillsModel.self) private var skillsModel

    var body: some View {
        let isManagedBySkillport = skillsModel.isManagedSkill(skill)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name).font(.headline)
                    if let d = skill.frontmatter.description {
                        Text(d)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                Spacer()
                UpdateActions(
                    skill: skill,
                    isManagedBySkillport: isManagedBySkillport,
                    onApplyUpdate: onApplyUpdate,
                    onDismissUpdate: onDismissUpdate
                )
                Button(action: onOpen) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit SKILL.md")
                if isManagedBySkillport {
                    Button(role: .destructive, action: onUninstall) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Delete Skill"))
                }
            }
            AgentsRow(
                skill: skill,
                agents: skillsModel.agents,
                isManagedBySkillport: isManagedBySkillport,
                onToggle: onToggle
            )
        }
        .padding(.vertical, 6)
    }
}

private struct UpdateActions: View {
    let skill: Skill
    let isManagedBySkillport: Bool
    let onApplyUpdate: () -> Void
    let onDismissUpdate: (String) -> Void

    var body: some View {
        if case .available(let remoteHash) = skill.updateStatus, isManagedBySkillport {
            HStack(spacing: 6) {
                Button(action: onApplyUpdate) {
                    Label(String(localized: "Update"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Update this skill"))

                Button {
                    onDismissUpdate(remoteHash)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Dismiss this update"))
            }
        }
    }
}

private struct AgentsRow: View {
    let skill: Skill
    let agents: [Agent]
    let isManagedBySkillport: Bool
    let onToggle: (AgentID, Bool) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(agents, id: \.id) { agent in
                AgentChip(
                    agent: agent,
                    assignment: agent.assignmentStatus(for: skill),
                    isManagedBySkillport: isManagedBySkillport,
                    onToggle: { install in onToggle(agent.id, install) }
                )
            }
        }
    }
}

private struct AgentChip: View {
    let agent: Agent
    let assignment: AgentAssignmentStatus
    let isManagedBySkillport: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(assignment == .notAssigned)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                Text(agent.id.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .opacity(agent.isInstalled ? 1 : 0.48)
        .help(helpText)
        .accessibilityLabel("\(agent.id.displayName), \(statusText)")
        .accessibilityHint(accessibilityHint)
    }

    private var isActionable: Bool {
        guard isManagedBySkillport else { return false }
        switch assignment {
        case .direct:
            return true
        case .inherited:
            return false
        case .notAssigned:
            return agent.isInstalled
        }
    }

    private var systemImage: String {
        switch assignment {
        case .direct:
            return "link"
        case .inherited:
            return "arrow.triangle.branch"
        case .notAssigned:
            return "circle"
        }
    }

    private var background: Color {
        switch assignment {
        case .direct:
            return Color.accentColor.opacity(0.2)
        case .inherited:
            return Color.secondary.opacity(0.12)
        case .notAssigned:
            return Color.secondary.opacity(0.08)
        }
    }

    private var foreground: Color {
        switch assignment {
        case .direct:
            return Color.accentColor
        case .inherited:
            return Color.secondary
        case .notAssigned:
            return agent.isInstalled ? Color.secondary : Color.secondary.opacity(0.75)
        }
    }

    private var helpText: String {
        let availability = agent.isInstalled ? "" : " CLI/config not detected on this Mac."
        if !isManagedBySkillport {
            return
                "\(agent.id.displayName): external assignment. Import the skill into Skillport before changing links.\(availability)"
        }
        switch assignment {
        case .direct:
            return "\(agent.id.displayName): direct link. Click to unlink.\(availability)"
        case .inherited:
            return
                "\(agent.id.displayName): inherited through fallback. It can use this skill without a direct link.\(availability)"
        case .notAssigned:
            if agent.isInstalled {
                return "\(agent.id.displayName): not assigned. Click to create a direct link."
            }
            return "\(agent.id.displayName): not assigned; CLI/config not detected on this Mac."
        }
    }

    private var statusText: String {
        switch assignment {
        case .direct:
            return "Direct link"
        case .inherited:
            return "Inherited"
        case .notAssigned:
            return "Not assigned"
        }
    }

    private var accessibilityHint: String {
        switch assignment {
        case .direct:
            return isManagedBySkillport ? "Unlinks this skill from the agent." : helpText
        case .inherited:
            return "This agent receives the skill through a fallback directory."
        case .notAssigned:
            return isActionable ? "Creates a direct link for this agent." : helpText
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        return layout(subviews: subviews, width: width).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (sv, rect) in zip(subviews, result.rects) {
            sv.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                proposal: .init(rect.size)
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (rects: [CGRect], size: CGSize) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rects: [CGRect] = []
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rects.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return (rects, CGSize(width: width, height: y + rowHeight))
    }
}
