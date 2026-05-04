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
        if fm.fileExists(atPath: canonicalBase.path),
            let entries = try? fm.contentsOfDirectory(
                at: canonicalBase,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        {
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

    /// Two-pass detection, mirroring parent repo's `findInstallations`:
    ///   Pass 1 — direct symlink at `agent.skillsDir/<name>` pointing to canonical.
    ///   Pass 2 — any `agent.fallbackChain/<name>` whose realpath matches canonical
    ///            (soft inheritance; e.g. codex reads `.agents/skills` via fallback).
    private func detectInstalledAgents(home: URL, canonicalSkill: URL) -> Set<AgentID> {
        var result: Set<AgentID> = []
        // Resolve /var -> /private/var (macOS symlink) so path comparison is reliable.
        let resolvedCanonical = canonicalSkill.resolvingSymlinksInPath().path
        let skillName = canonicalSkill.lastPathComponent

        for agent in Agent.defaultAgents(home: home) {
            if matchesCanonical(
                at: agent.skillsDir.appendingPathComponent(skillName),
                canonical: resolvedCanonical
            ) {
                result.insert(agent.id)
                continue
            }
            for fallback in agent.fallbackChain {
                if matchesCanonical(
                    at: fallback.appendingPathComponent(skillName),
                    canonical: resolvedCanonical
                ) {
                    result.insert(agent.id)
                    break
                }
            }
        }
        return result
    }

    /// True when `candidate` exists (as symlink or real directory) and resolves to `canonical`.
    private func matchesCanonical(at candidate: URL, canonical: String) -> Bool {
        let fm = FileManager.default
        if let raw = try? fm.destinationOfSymbolicLink(atPath: candidate.path) {
            let target = raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw)
                : candidate.deletingLastPathComponent().appendingPathComponent(raw)
            return target.resolvingSymlinksInPath().path == canonical
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate.resolvingSymlinksInPath().path == canonical
        }
        return false
    }
}
