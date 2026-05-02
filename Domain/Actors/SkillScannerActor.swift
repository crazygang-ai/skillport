import Foundation

public actor SkillScannerActor {
    public init() {}

    /// 扫描 `~/.agents/skills` 作为规范存储，然后检查 11 个 agent 目录的 symlink 判断安装状态。
    public func scanAll(home: URL) async throws -> [Skill] {
        let fm = FileManager.default
        let canonicalBase = home.appendingPathComponent(".agents/skills", isDirectory: true)

        guard fm.fileExists(atPath: canonicalBase.path) else { return [] }

        let entries = try fm.contentsOfDirectory(
            at: canonicalBase,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var skills: [Skill] = []
        for entry in entries {
            let skillMd = entry.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMd.path) else { continue }
            let raw = (try? String(contentsOf: skillMd, encoding: .utf8)) ?? ""
            let parsed = (try? SKILLMdParser.parse(raw)) ?? .init(metadata: SKILLMetadata(), body: raw)
            let name = entry.lastPathComponent
            let source: SkillSource = .local(path: entry)  // 默认，Installer/更新后会改写
            let installedAgents = detectInstalledAgents(home: home, canonicalSkill: entry)
            let skill = Skill(
                name: name,
                path: entry,
                source: source,
                frontmatter: parsed.metadata,
                installedAgents: installedAgents,
                updateStatus: .unknown
            )
            skills.append(skill)
        }
        return skills.sorted { $0.name < $1.name }
    }

    private func detectInstalledAgents(home: URL, canonicalSkill: URL) -> Set<AgentID> {
        var result: Set<AgentID> = []
        let fm = FileManager.default
        // Resolve /var -> /private/var (macOS symlink) so path comparison is reliable.
        let resolvedCanonical = canonicalSkill.resolvingSymlinksInPath().path
        for agent in Agent.defaultAgents(home: home) {
            let link = agent.skillsDir.appendingPathComponent(canonicalSkill.lastPathComponent)
            if let rawTarget = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                let resolvedTarget = URL(fileURLWithPath: rawTarget).resolvingSymlinksInPath().path
                if resolvedTarget == resolvedCanonical {
                    result.insert(agent.id)
                }
            }
        }
        return result
    }
}
