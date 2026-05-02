import Foundation
import Observation

public struct Toast: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let level: NotificationLevel
    public let message: String
    public let createdAt: Date

    public init(level: NotificationLevel, message: String) {
        self.id = UUID()
        self.level = level
        self.message = message
        self.createdAt = Date()
    }
}

@MainActor
@Observable
public final class NotificationModel {
    public var toasts: [Toast] = []

    public init() {}

    public func post(_ toast: Toast) {
        toasts.append(toast)
    }

    public func dismiss(id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}
