import Foundation

public struct AgentDetector: Sendable {
    private let pathOverride: String?

    public init(pathOverride: String? = nil) {
        self.pathOverride = pathOverride
    }

    public func isInstalled(agentID: AgentID) async throws -> Bool {
        let paths = (pathOverride ?? ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let binaryName = agentID.binaryName
        for dir in paths {
            let candidate = dir + "/" + binaryName
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir),
                !isDir.boolValue,
                FileManager.default.isExecutableFile(atPath: candidate)
            {
                return true
            }
        }
        return false
    }

    public func detectAll() async throws -> [AgentID: Bool] {
        var result: [AgentID: Bool] = [:]
        for id in AgentID.allCases {
            result[id] = try await isInstalled(agentID: id)
        }
        return result
    }
}
