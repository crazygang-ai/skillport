import Foundation

public enum SkillportError: Error, Sendable {
    case parseFailed(reason: String)
}
