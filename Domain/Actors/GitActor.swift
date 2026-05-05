import Foundation

public actor GitActor {
    private let proxySettings: ProxySettingsActor?
    private let keychain: KeychainActor?
    private let executableURL: URL
    private let commandPrefix: [String]
    private let commandTimeout: Duration

    public init(
        proxySettings: ProxySettingsActor? = nil,
        keychain: KeychainActor? = nil,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        commandPrefix: [String] = ["git"],
        commandTimeout: Duration = .seconds(120)
    ) {
        self.proxySettings = proxySettings
        self.keychain = keychain
        self.executableURL = executableURL
        self.commandPrefix = commandPrefix
        self.commandTimeout = commandTimeout
    }

    @discardableResult
    public func headHash(in repo: URL) async throws -> String {
        try await run(["rev-parse", "HEAD"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func treeHash(in repo: URL, ref: String = "HEAD") async throws -> String {
        let out = try await run(["rev-parse", "\(ref)^{tree}"], in: repo)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `git rev-parse <ref>:<subdir>` — 获取某个子目录的 tree hash。
    /// subdir 为空或 "." 时退化到整仓 treeHash。用于更新检测：以 subdir tree hash 做基线，
    /// 能精确定位单 skill 的变更，不受仓内其它 subdir 影响。
    public func subdirTreeHash(in repo: URL, subdir: String, ref: String = "HEAD") async throws -> String {
        let trimmed = subdir.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty || trimmed == "." {
            return try await treeHash(in: repo, ref: ref)
        }
        let out = try await run(["rev-parse", "\(ref):\(trimmed)"], in: repo)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func remoteCommitHash(url: URL, ref: String) async throws -> String {
        let out = try await run(["ls-remote", url.absoluteString, ref], in: nil)
        // 输出: "<commit-hash>\trefs/heads/<ref>"
        let hash = out.split(separator: "\t").first.map(String.init) ?? ""
        return hash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func fetch(in repo: URL, ref: String? = nil) async throws {
        var args = ["fetch", "--depth", "1", "origin"]
        if let ref, !ref.isEmpty { args.append(ref) }
        _ = try await run(args, in: repo)
    }

    public func checkout(in repo: URL, ref: String) async throws {
        _ = try await run(["checkout", "-f", ref], in: repo)
    }

    public func resetHard(in repo: URL, ref: String) async throws {
        _ = try await run(["reset", "--hard", ref], in: repo)
    }

    public func cloneLocal(from source: URL, to dest: URL, depth: Int?) async throws {
        var args = ["clone", source.path, dest.path]
        if let depth {
            args.insert(contentsOf: ["--depth", String(depth)], at: 1)
        }
        _ = try await run(args, in: nil)
    }

    public func clone(url: URL, to dest: URL, ref: String, depth: Int? = 1) async throws {
        var args = ["clone"]
        if let depth { args.append(contentsOf: ["--depth", String(depth)]) }
        // `git clone -b HEAD` is rejected by git. Treat empty/"HEAD" as "use remote default".
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "HEAD" {
            args.append(contentsOf: ["-b", trimmed])
        }
        args.append(contentsOf: [url.absoluteString, dest.path])
        _ = try await run(args, in: nil)
    }

    public func pull(in repo: URL) async throws {
        _ = try await run(["pull", "--ff-only"], in: repo)
    }

    private func run(_ args: [String], in cwd: URL?) async throws -> String {
        let environment = await processEnvironment()
        let executableURL = executableURL
        let commandPrefix = commandPrefix
        let timeout = commandTimeout
        let box = GitProcessBox()

        return try await withTaskCancellationHandler(
            operation: {
                try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        try await Self.runProcess(
                            args,
                            in: cwd,
                            environment: environment,
                            executableURL: executableURL,
                            commandPrefix: commandPrefix,
                            processBox: box
                        )
                    }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        box.terminate()
                        throw SkillportError.gitFailed(
                            exitCode: -2,
                            stderr: "git timed out after \(timeout)"
                        )
                    }

                    do {
                        guard let output = try await group.next() else {
                            throw SkillportError.gitFailed(exitCode: -1, stderr: "git task did not start")
                        }
                        group.cancelAll()
                        return output
                    } catch {
                        group.cancelAll()
                        throw error
                    }
                }
            },
            onCancel: {
                box.terminate()
            }
        )
    }

    private nonisolated static func runProcess(
        _ args: [String],
        in cwd: URL?,
        environment: [String: String],
        executableURL: URL,
        commandPrefix: [String],
        processBox: GitProcessBox
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = commandPrefix + args
            if let cwd { process.currentDirectoryURL = cwd }
            if !environment.isEmpty {
                process.environment = environment
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            // Drain pipes concurrently so git never blocks on full pipe buffers
            // (classic Process deadlock when using waitUntilExit + readDataToEndOfFile).
            let sink = PipeSink()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    sink.appendStdout(data)
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    sink.appendStderr(data)
                }
            }

            process.terminationHandler = { proc in
                // Drain any residual bytes and detach handlers.
                let restOut = try? stdout.fileHandleForReading.readToEnd()
                let restErr = try? stderr.fileHandleForReading.readToEnd()
                if let restOut { sink.appendStdout(restOut) }
                if let restErr { sink.appendStderr(restErr) }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                processBox.clear(proc)

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: sink.stdoutString())
                } else {
                    continuation.resume(
                        throwing: SkillportError.gitFailed(
                            exitCode: proc.terminationStatus,
                            stderr: sink.stderrString()
                        )
                    )
                }
            }

            do {
                processBox.set(process)
                try process.run()
            } catch {
                processBox.clear(process)
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(
                    throwing: SkillportError.gitFailed(exitCode: -1, stderr: "\(error)")
                )
            }
        }
    }

    public func effectiveProxyEnvironmentForTesting(password: String? = nil) async -> [String: String] {
        guard let proxySettings else { return [:] }
        return await proxySettings.proxyEnvironment(password: password)
    }

    private func processEnvironment() async -> [String: String] {
        guard let proxySettings else { return [:] }
        let password: String?
        if let keychain {
            password = try? await keychain.get(account: ProxySettingsActor.proxyPasswordAccount)
        } else {
            password = nil
        }
        let proxyEnv = await proxySettings.proxyEnvironment(password: password)
        guard !proxyEnv.isEmpty else { return [:] }
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in proxyEnv {
            environment[key] = value
        }
        return environment
    }
}

/// Thread-safe accumulator for stdout/stderr pipe reads.
private final class PipeSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        stdoutData.append(data)
    }
    func appendStderr(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        stderrData.append(data)
    }
    func stdoutString() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
    func stderrString() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: stderrData, encoding: .utf8) ?? ""
    }
}

private final class GitProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}
