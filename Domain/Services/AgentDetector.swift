import Foundation

public struct AgentDetector: Sendable {
    private let pathOverride: String?
    private let shellOverride: String?
    private let fallbackPathOverride: String?
    private let loginShellTimeout: Duration

    public init(
        pathOverride: String? = nil,
        shellOverride: String? = nil,
        fallbackPathOverride: String? = nil,
        loginShellTimeout: Duration = .seconds(3)
    ) {
        self.pathOverride = pathOverride
        self.shellOverride = shellOverride
        self.fallbackPathOverride = fallbackPathOverride
        self.loginShellTimeout = loginShellTimeout
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
        return fallbackPathOverride ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
    }

    private func loginShellPath() async -> String? {
        let shell = shellOverride ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let timeout = loginShellTimeout
        let box = LoginShellProcessBox()
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await Self.runLoginShellPath(shell: shell, processBox: box)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                box.terminate()
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            box.terminate()
            return result
        }
    }

    private static func runLoginShellPath(
        shell: String,
        processBox: LoginShellProcessBox
    ) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell)
            // `-ilc` runs an interactive login shell so both `.zprofile` and `.zshrc`
            // get sourced — nvm/pyenv/asdf typically inject PATH from rc, not profile.
            // `printf` avoids trailing-newline quirks.
            p.arguments = ["-ilc", "printf %s \"$PATH\""]
            let out = Pipe()
            let err = Pipe()
            let sink = LoginShellPipeSink()
            p.standardOutput = out
            p.standardError = err
            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    sink.appendStdout(data)
                }
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    sink.appendStderr(data)
                }
            }
            p.terminationHandler = { _ in
                let restOut = try? out.fileHandleForReading.readToEnd()
                let restErr = try? err.fileHandleForReading.readToEnd()
                if let restOut { sink.appendStdout(restOut) }
                if let restErr { sink.appendStderr(restErr) }
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                let s = sink.stdoutString()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty {
                    continuation.resume(returning: s)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            do {
                processBox.set(p)
                try p.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                p.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}

private final class LoginShellProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

private final class LoginShellPipeSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) {
        lock.lock()
        stdoutData.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrData.append(data)
        lock.unlock()
    }

    func stdoutString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
