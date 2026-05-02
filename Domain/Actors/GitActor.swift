import Foundation

public actor GitActor {
    public init() {}

    @discardableResult
    public func headHash(in repo: URL) async throws -> String {
        try await run(["rev-parse", "HEAD"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func treeHash(in repo: URL, ref: String = "HEAD") async throws -> String {
        let out = try await run(["rev-parse", "\(ref)^{tree}"], in: repo)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func remoteTreeHash(url: URL, ref: String) async throws -> String {
        let out = try await run(["ls-remote", url.absoluteString, ref], in: nil)
        // 输出: "<commit-hash>\trefs/heads/<ref>"
        let hash = out.split(separator: "\t").first.map(String.init) ?? ""
        return hash.trimmingCharacters(in: .whitespacesAndNewlines)
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
        args.append(contentsOf: ["-b", ref, url.absoluteString, dest.path])
        _ = try await run(args, in: nil)
    }

    public func pull(in repo: URL) async throws {
        _ = try await run(["pull", "--ff-only"], in: repo)
    }

    private func run(_ args: [String], in cwd: URL?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            if let cwd { process.currentDirectoryURL = cwd }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SkillportError.gitFailed(exitCode: -1, stderr: "\(error)"))
                return
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let err =
                    String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                continuation.resume(
                    throwing: SkillportError.gitFailed(
                        exitCode: process.terminationStatus,
                        stderr: err
                    ))
            } else {
                let out =
                    String(
                        data: stdout.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                continuation.resume(returning: out)
            }
        }
    }
}
