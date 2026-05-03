# Skillport

Native macOS app for managing AI agent skills. Rewrite of [SkillPilot](https://github.com/crazygang-ai/skillpilot) in Swift/SwiftUI.

**Status:** Early development. Not yet released.

## Features

- Scan `~/.agents/skills/` + parse SKILL.md frontmatter (Yams)
- Finder drag-and-drop + `Cmd+N` local skill import
- Per-agent symlink toggles across 11 agents (Claude Code, Codex, Gemini, Copilot, ...)
- Editor with frontmatter form, CodeEditor body, live Markdown preview, atomic save
- FSEvents-triggered auto-rescan
- Registry browser (skills.sh) with search, leaderboard, HTML+Markdown preview, one-click install
- Native Settings panel (General / Network / Updates / About) with Keychain-backed proxy password
- MenuBarExtra mini dashboard with skill count + updates badge
- Quick Look extension for native SKILL.md preview in Finder
- i18n (en + zh-Hans)
- Sparkle 2 auto-update bridge (feed URL pending M7)

## Requirements

- macOS 15 Sequoia or later
- Xcode 16+ (for building from source)

## Build from source

```bash
./Scripts/bootstrap.sh        # installs XcodeGen via Homebrew if missing
./Scripts/generate-project.sh # regenerates Skillport.xcodeproj
open Skillport.xcodeproj
```

## License

MIT
