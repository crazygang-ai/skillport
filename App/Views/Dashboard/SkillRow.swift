import SwiftUI

struct SkillRow: View {
    let skill: Skill
    let onToggle: (AgentID, Bool) -> Void
    let onOpen: () -> Void
    let onUninstall: () -> Void
    let onCopyPath: () -> Void
    let onRevealInFinder: () -> Void
    let onApplyUpdate: () -> Void
    let onDismissUpdate: (String) -> Void

    @Environment(SkillsModel.self) private var skillsModel
    @Environment(\.appStrings) private var strings

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
                Button(action: onCopyPath) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(strings("Copy skill path"))
                Button(action: onRevealInFinder) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(strings("Reveal in Finder"))
                Button(action: onOpen) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(strings("Edit SKILL.md"))
                if isManagedBySkillport {
                    Button(role: .destructive, action: onUninstall) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(strings("Delete Skill"))
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
    @Environment(\.appStrings) private var strings

    var body: some View {
        if case .available(let remoteHash) = skill.updateStatus, isManagedBySkillport {
            HStack(spacing: 6) {
                Button(action: onApplyUpdate) {
                    Label(strings("Update"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help(strings("Update this skill"))

                Button {
                    onDismissUpdate(remoteHash)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help(strings("Dismiss this update"))
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
    @Environment(\.appStrings) private var strings

    var body: some View {
        Button {
            onToggle(assignment == .notAssigned)
        } label: {
            HStack(spacing: 5) {
                AgentIcon(agentID: agent.id, isInstalled: agent.isInstalled, size: 16)
                Text(agent.id.displayName)
                    .font(.caption)
                if let statusSystemImage {
                    Image(systemName: statusSystemImage)
                        .font(.caption2)
                        .foregroundStyle(statusForeground)
                }
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

    private var statusSystemImage: String? {
        switch assignment {
        case .direct:
            return "link"
        case .inherited:
            return "arrow.triangle.branch"
        case .notAssigned:
            return nil
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

    private var statusForeground: Color {
        switch assignment {
        case .direct:
            return Color.accentColor
        case .inherited:
            return Color.secondary
        case .notAssigned:
            return Color.clear
        }
    }

    private var helpText: String {
        if !isManagedBySkillport {
            if agent.isInstalled {
                return strings(
                    "\(agent.id.displayName): external assignment. Import the skill into Skillport before changing links."
                )
            }
            return strings(
                "\(agent.id.displayName): external assignment. Import the skill into Skillport before changing links. CLI/config not detected on this Mac."
            )
        }
        switch assignment {
        case .direct:
            if agent.isInstalled {
                return strings("\(agent.id.displayName): direct link. Click to unlink.")
            }
            return strings(
                "\(agent.id.displayName): direct link. Click to unlink. CLI/config not detected on this Mac."
            )
        case .inherited:
            if agent.isInstalled {
                return strings(
                    "\(agent.id.displayName): inherited through fallback. It can use this skill without a direct link."
                )
            }
            return strings(
                "\(agent.id.displayName): inherited through fallback. It can use this skill without a direct link. CLI/config not detected on this Mac."
            )
        case .notAssigned:
            if agent.isInstalled {
                return strings("\(agent.id.displayName): not assigned. Click to create a direct link.")
            }
            return strings("\(agent.id.displayName): not assigned; CLI/config not detected on this Mac.")
        }
    }

    private var statusText: String {
        switch assignment {
        case .direct:
            return strings("Direct link")
        case .inherited:
            return strings("Inherited")
        case .notAssigned:
            return strings("Not assigned")
        }
    }

    private var accessibilityHint: String {
        switch assignment {
        case .direct:
            return isManagedBySkillport ? strings("Unlinks this skill from the agent.") : helpText
        case .inherited:
            return strings("This agent receives the skill through a fallback directory.")
        case .notAssigned:
            return isActionable ? strings("Creates a direct link for this agent.") : helpText
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
