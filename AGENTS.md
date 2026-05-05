# AGENTS.md

This file provides guidance to Codex when working with Skillport.

## Build & Run

```bash
./Scripts/bootstrap.sh              # one-time
./Scripts/generate-project.sh       # regenerate after project.yml changes
xcodebuild -scheme Skillport build  # CLI build
xcodebuild -scheme Skillport -derivedDataPath build/DerivedData -destination platform=macOS,arch=arm64 CODE_SIGNING_ALLOWED=NO test -quiet
```

## Architecture

三层：SwiftUI Views → `@Observable` Models → Domain Actors。事件通过 `AsyncStream<DomainEvent>` 从 actor 流向 model。View 不直接触碰 actor。

关键文件：`Domain/Actors/SkillManagerActor.swift` 是中心编排器。所有 actor 定义在 `Domain/Actors/`，纯类型在 `Domain/Types/`。

## Agent UI Semantics

- UI 展示 agent 时以 `Agent.defaultAgents(home:)` 为全集；不要因为 `Agent.isInstalled == false` 把 agent 隐藏。
- `AgentStatus.isInstalled` 只表示本机可用性信号（binary/config/skillsDir），用于灰态/禁用安装动作。
- Skill assignment 以 `Agent.assignmentStatus(for:)` 为准：Skillport-managed skill 的 `direct` 可 toggle，`inherited` 通过 fallback 继承，不应提供“取消继承”的误导性 toggle；外部 CLI 直接安装的 skill 只展示状态，不直接改 links。
- Sidebar 的 agent 数量来自 `Skill.installedAgents`，即使某个 CLI 未安装，也应能显示 inherited 的数量。

## Conventions

- 原子写：先 `.tmp` + `FileManager.replaceItemAt`
- YAML 用 Yams；Markdown 用 swift-markdown
- 文件系统即数据库，不引二级持久化
- 测试不 mock 文件系统 / git / Keychain；仅 URLSession 层打桩
- Swift 6 strict concurrency 必须过
- Lockfile 版本永远 3

## Related

Design notes: see `docs/`.
