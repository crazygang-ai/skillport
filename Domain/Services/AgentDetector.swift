import Foundation

public struct AgentDetector: Sendable {
    private let pathOverride: String?

    public init(pathOverride: String? = nil) {
        self.pathOverride = pathOverride
    }

    public func isInstalled(agentID: AgentID) async throws -> Bool {
        let searchPath = await resolvedSearchPath()
        return binaryOnPath(agentID: agentID, in: searchPath)
    }

    public func detectAll() async throws -> [AgentID: Bool] {
        // Resolve once — login-shell probe is the slow bit, no sense doing it 11 times.
        let searchPath = await resolvedSearchPath()
        var result: [AgentID: Bool] = [:]
        for id in AgentID.allCases {
            result[id] = binaryOnPath(agentID: id, in: searchPath)
        }
        return result
    }

    /// 为每个 agent 汇总三路信号：PATH 上的二进制、configDir、skillsDir。
    /// GUI 启动时 PATH 可能不完整；configDir / skillsDir 也作为可用性信号。
    public func detectAllStatuses(home: URL) async throws -> [AgentID: AgentStatus] {
        let searchPath = await resolvedSearchPath()
        let fm = FileManager.default
        var result: [AgentID: AgentStatus] = [:]
        for agent in Agent.defaultAgents(home: home) {
            let onPath = binaryOnPath(agentID: agent.id, in: searchPath)
            let configExists = agent.configDir.map { fm.fileExists(atPath: $0.path) } ?? false
            let skillsExists = fm.fileExists(atPath: agent.skillsDir.path)
            let skillCount = skillsExists ? countValidSkills(in: agent.skillsDir) : 0
            result[agent.id] = AgentStatus(
                binaryOnPath: onPath,
                configDirExists: configExists,
                skillsDirExists: skillsExists,
                skillCount: skillCount
            )
        }
        return result
    }

    // MARK: - Internals

    private func binaryOnPath(agentID: AgentID, in searchPath: String) -> Bool {
        let binaryName = agentID.binaryName
        for dir in searchPath.split(separator: ":").map(String.init) {
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

    private func countValidSkills(in skillsDir: URL) -> Int {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: skillsDir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        return entries.filter { entry in
            guard !entry.lastPathComponent.hasPrefix(".") else { return false }
            let resolved = entry.resolvingSymlinksInPath()
            return FileManager.default.fileExists(
                atPath: resolved.appendingPathComponent("SKILL.md").path
            )
        }.count
    }

    /// GUI apps on macOS inherit a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) so
    /// Homebrew, nvm, pyenv, cargo, etc. are invisible. Run a login shell once to pick
    /// up the user's real PATH from rc files. Falls back to the process PATH if that fails.
    private func resolvedSearchPath() async -> String {
        if let override = pathOverride { return override }
        if let loginPath = await loginShellPath(), !loginPath.isEmpty {
            return loginPath
        }
        return ProcessInfo.processInfo.environment["PATH"] ?? ""
    }

    private func loginShellPath() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell)
            // `-ilc` runs an interactive login shell so both `.zprofile` and `.zshrc`
            // get sourced — nvm/pyenv/asdf typically inject PATH from rc, not profile.
            // `printf` avoids trailing-newline quirks.
            p.arguments = ["-ilc", "printf %s \"$PATH\""]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            p.terminationHandler = { _ in
                let data = (try? out.fileHandleForReading.readToEnd()) ?? nil ?? Data()
                let s = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let s, !s.isEmpty {
                    continuation.resume(returning: s)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            do {
                try p.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
