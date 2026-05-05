import Foundation

public actor SkillScannerActor {
    public init() {}

    /// 扫描 `~/.agents/skills` 作为规范存储；同时遍历每个 agent 的 skillsDir 收录
    /// 仅存在于 agent 目录下的 "外部" skill（例如 `claude skill install` 直接装进 .claude/skills）。
    /// 按 realpath 去重，避免 symlink 与 canonical 双算。
    public func scanAll(home: URL) async throws -> [Skill] {
        let fm = FileManager.default
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)
        let canonicalBasePath = canonicalBase.resolvingSymlinksInPath().path

        var byRealPath: [String: Skill] = [:]

        // Pass 1 — canonical store
        if fm.fileExists(atPath: canonicalBase.path) {
            let entries: [URL]
            do {
                entries = try fm.contentsOfDirectory(
                    at: canonicalBase,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw SkillportError.fileIO(
                    path: canonicalBase,
                    reason: "failed to list canonical skills: \(error.localizedDescription)"
                )
            }
            for entry in entries {
                guard fm.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path) else { continue }
                let key = entry.resolvingSymlinksInPath().path
                byRealPath[key] = makeSkill(at: entry, home: home)
            }
        }

        // Pass 2 — foreign skills: entries in an agent's skillsDir whose realpath
        // is outside the canonical base. Merged by realpath to unify across agents.
        for agent in Agent.defaultAgents(home: home) {
            let dir = agent.skillsDir
            guard fm.fileExists(atPath: dir.path) else { continue }
            guard
                let entries = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }
            for entry in entries {
                let realPath = entry.resolvingSymlinksInPath().path
                if byRealPath[realPath] != nil { continue }
                if realPath == canonicalBasePath || realPath.hasPrefix(canonicalBasePath + "/") {
                    continue
                }
                let realURL = URL(fileURLWithPath: realPath)
                guard fm.fileExists(atPath: realURL.appendingPathComponent("SKILL.md").path) else { continue }
                byRealPath[realPath] = makeSkill(at: realURL, home: home)
            }
        }

        return byRealPath.values.sorted { $0.name < $1.name }
    }

    private func makeSkill(at path: URL, home: URL) -> Skill {
        let raw = (try? String(contentsOf: path.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let parsed = (try? SKILLMdParser.parse(raw)) ?? .init(metadata: SKILLMetadata(), body: raw)
        return Skill(
            name: path.lastPathComponent,
            path: path,
            source: .local(path: path),  // 默认；SkillManagerActor.rescan 会用 lockfile 覆盖真实 source
            frontmatter: parsed.metadata,
            installedAgents: detectInstalledAgents(home: home, canonicalSkill: path),
            updateStatus: .unknown
        )
    }

    /// Two-pass detection:
    ///   Pass 1 — direct symlink at `agent.skillsDir/<name>` pointing to canonical.
    ///   Pass 2 — any `agent.fallbackChain/<name>` whose realpath matches canonical
    ///            (soft inheritance; e.g. codex reads `.agents/skills` via fallback).
    private func detectInstalledAgents(home: URL, canonicalSkill: URL) -> Set<AgentID> {
        var result: Set<AgentID> = []

        for agent in Agent.defaultAgents(home: home) {
            if agent.assignmentStatus(forSkillAt: canonicalSkill).isAssigned {
                result.insert(agent.id)
            }
        }
        return result
    }
}
