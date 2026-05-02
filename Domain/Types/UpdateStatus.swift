import Foundation

public enum UpdateStatus: Codable, Hashable, Sendable {
    case upToDate
    case available(remoteHash: String)
    case unknown

    public var isUpToDate: Bool {
        if case .upToDate = self { return true }
        return false
    }

    public var pendingRemoteHash: String? {
        if case .available(let hash) = self { return hash }
        return nil
    }
}
