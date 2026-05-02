# CLAUDE.md

This file provides guidance to Claude Code when working with Skillport.

## Build & Run

```bash
./Scripts/bootstrap.sh              # one-time
./Scripts/generate-project.sh       # regenerate after project.yml changes
xcodebuild -scheme Skillport build  # CLI build
xcodebuild -scheme Skillport test   # run unit tests
```

## Architecture

三层：SwiftUI Views → `@Observable` Models → Domain Actors。事件通过 `AsyncStream<DomainEvent>` 从 actor 流向 model。View 不直接触碰 actor。

关键文件：`Domain/Actors/SkillManagerActor.swift` 是中心编排器。所有 actor 定义在 `Domain/Actors/`，纯类型在 `Domain/Types/`。

## Conventions

- 原子写：先 `.tmp` + `FileManager.replaceItemAt`
- YAML 用 Yams；Markdown 用 swift-markdown
- 文件系统即数据库，不引二级持久化
- 测试不 mock 文件系统 / git / Keychain；仅 URLSession 层打桩
- Swift 6 strict concurrency 必须过
- Lockfile 版本永远 3

## Related

Parent repo: `crazygang-ai/skillpilot` (Electron 版，保持独立演进)
Design spec: 参见 parent repo `docs/superpowers/specs/2026-05-02-skillport-native-rewrite-design.md`
