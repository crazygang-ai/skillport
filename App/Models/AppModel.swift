import Foundation
import Observation

public enum AppSection: Hashable, Sendable {
    case dashboard
    case registry
    case editor(skillID: SkillIdentity?)
}

@MainActor
@Observable
public final class AppModel {
    public var section: AppSection = .dashboard
    public var currentAgentFilter: AgentID?

    public init() {}

    public func setSection(_ s: AppSection) { section = s }
    public func selectAgent(_ id: AgentID?) { currentAgentFilter = id }
    public func openEditor(for id: SkillIdentity?) { section = .editor(skillID: id) }
}
