# Skillport 项目接力 — 新 session 启动 prompt（M7 + polish 完工）

复制本文件（`docs/handoff-2026-05-03-m7-polish.md`）全部内容作为新 session 第一条消息。

---

## 项目背景

Skillport = macOS 原生管理 AI agent skills 的 SwiftUI app。

**仓库位置**：
- 主项目代码：`/Users/crazy/own_project/skillport/`（push 到 `git@github.com:crazygang-ai/skillport.git` 的 `main`）
- Plan/spec 文档：`/Users/crazy/own_project/skillpilot/docs/superpowers/`
  - spec: `specs/2026-05-02-skillport-native-rewrite-design.md`
  - M1-M4 plan: `plans/2026-05-02-skillport-m1-m4-foundation.md`
  - M5 plan: `plans/2026-05-03-skillport-m5-registry.md`
  - M6 plan: `plans/2026-05-03-skillport-m6-polish-and-i18n.md`
  - **M7+polish plan: `plans/2026-05-03-skillport-m7-and-polish.md`**

## 当前状态（M7 脚手架 + polish 完工）

- **M1–M7 完工**（M7 是脚手架，端到端发布要用户跑 RELEASE-SETUP.md）
- **166/166 tests 绿**
- Swift 6 `SWIFT_STRICT_CONCURRENCY: complete` 0 error
- swift-format lint 0 warning（`App Domain Tests SkillportPreview` 四目录）
- 本机 Xcode 26.4 / Swift 6.3；CI `macos-15` + Xcode 16 / Swift 6.0
- 5 个 SPM 依赖（同 M6）
- 2 个 target（同 M6）
- `./Scripts/check-parser-parity.sh` ✅

**本次批量完工的功能**：

### Phase 1：多-skill repo App 内 install（M5 ADR-M5-2 欠账清偿）
- `SkillInstallerActor.installGitHub` 新增 `skillId` 参数 + sourceURL overload
- Multi-skill 走 "clone to tmp → move subdir to canonical → clean tmp" 策略
- Canonical dir 用 `skillId` 命名（与 `npx skills add --skill X` 的用户语义一致）
- `RegistryModel.installSelected` 取消 `isSingleSkillRepo` gate
- RegistryDetailPanel Install 按钮对所有 entry 启用
- 新 test helper `Tests/SkillportTests/TestSupport/GitFixtures.swift`（造本地 bare repo）

### Phase 2：Registry 渲染打磨
- 主 app `RegistryContentRenderer`：嵌套列表（2-space indent）+ GFM 表格（bold header + `|` separator）+ 图片占位符 `[Image: alt — url]`
- QL extension `SkillportPreview/MarkdownRenderer`：相同 3 条能力 port（NSAttributedString 版本）

### Phase 3：i18n 加 zh-Hant + ja
- `Localizable.xcstrings` 58 条 key 补全 zh-Hant + ja 翻译
- `GeneralTab` Language picker 4 选项（en / 简中 / 繁中 / 日本語）

### Phase 4：M7 发布流水线脚手架
- `build/ExportOptions.plist` 填完 Developer ID manual signing 配置
- `Scripts/release.sh` — bump version + tag + archive + export
- `Scripts/notarize.sh` — zip → notarytool submit → stapler staple
- `Scripts/publish-appcast.sh` — DMG + EdDSA sign + appcast.xml 生成
- `build/appcast.template.xml` — Sparkle 2 兼容的 RSS template
- `App/Resources/Info.plist` — `SUFeedURL` + `SUPublicEDKey` 占位符
- `AppUpdaterBridge` 从 Info.plist 读 feedURL（占位值自动禁用自动检查）
- `.github/workflows/release.yml` — v* tag 触发的 release workflow
- `docs/RELEASE-SETUP.md` — 6 步完整 checklist：Developer ID / notarize / EdDSA / appcast 托管 / GitHub Secrets / 首发命令

## 架构新增

- `Domain/Actors/SkillInstallerActor.swift` — 加 `installGitHub(sourceURL:...)` overload + subdir extraction
- `Tests/SkillportTests/TestSupport/GitFixtures.swift` — 本地 bare repo builder
- `Scripts/release.sh` / `notarize.sh` / `publish-appcast.sh`
- `.github/workflows/release.yml`
- `build/appcast.template.xml`
- `docs/RELEASE-SETUP.md`

## ADRs

1. **ADR-M7-1：Phase 4 只脚手架**。Developer ID 证书 / notarize credential / Sparkle EdDSA key / 发布域名都由用户按 RELEASE-SETUP.md 配置 — scripts 本地 dry-run 能过，端到端要 secrets 才能 green。

2. **ADR-M7-2：multi-skill install 走 full clone + subdir move**（非 sparse-checkout）。简单、健壮、容错好。代价是多存一份完整 repo 临时文件（skill repos 通常 <1 MB）。

3. **ADR-M7-3：Registry 渲染双路径都补**。主 app 和 QL extension 渲染器结构相似但 API 不同（SwiftUI AttributedString vs AppKit NSAttributedString），Phase 2 两处同等补齐。

## 关键踩坑备忘

1. **GitActor 有两种 clone API**：`clone(url:to:ref:depth:)` 用 `git clone -b <ref>` 要分支名；`cloneLocal(from:to:depth:)` 用于 file:// URL 不需 ref。多-skill 代码按 `sourceURL.isFileURL` 分路由

2. **`generate_keys`/`sign_update` Sparkle 工具** 在 SPM 集成后藏在 `~/Library/Developer/Xcode/DerivedData/Skillport-*/SourcePackages/artifacts/Sparkle/bin/`。`publish-appcast.sh` 里优先 `xcrun --find sign_update` 找，找不到再 fallback 到 DerivedData glob

3. **BSD sed 的 `-i` 要带 `''` 空字符串** 才能就地改：`sed -i '' 's/a/b/'`（Linux 的 GNU sed 是 `sed -i 's/a/b/'`）

4. **xcstrings 插值 key 必须用 format specifier**：`String(localized: "\(n: Int) items")` 运行时 key = `"%lld items"`，手写 xcstrings 要对齐此 key 而非 `\(n)`

5. **Info.plist 占位符自动禁用逻辑**：`AppUpdaterBridge.feedURLFromInfoPlist()` 把含 "YOUR_DOMAIN" 的 SUFeedURL 当空处理，Sparkle 不会尝试拉 feed — 开发时安全，release 前记得换真实 URL

## 构建与运行速查

```bash
cd /Users/crazy/own_project/skillport
./Scripts/bootstrap.sh
./Scripts/generate-project.sh
./Scripts/check-parser-parity.sh
xcodebuild -scheme Skillport -destination 'platform=macOS' test
swift-format lint --recursive App Domain Tests SkillportPreview
open Skillport.xcodeproj

# Release (需先按 docs/RELEASE-SETUP.md 配证书)
./Scripts/release.sh 0.1.0
./Scripts/notarize.sh build/export-0.1.0/Skillport.app
./Scripts/publish-appcast.sh build/export-0.1.0 0.1.0
git push && git push --tags
```

## 下一步候选

当前 Skillport 功能完备。剩下都是用户侧动作或可选打磨：

### A. 首次发布（需用户动作）
按 `docs/RELEASE-SETUP.md` 完成 6 步 → 跑 `release.sh` → 验证 Sparkle 自更新链路端到端

### B. 多-skill repo 的 update 流程
现在 `SkillUpdaterActor` 是 skillId-naive 的 — 多-skill repo 的 "update" 会重新 clone 整个 repo，但只更新一个 canonical dir。可以优化成只检查 subdir 的 tree hash

### C. Registry 图片实际加载
现在图片占位文字。实装要：Caching + URLSession + 隐私审查（HTTPS only, domain allowlist?）

### D. 繁中 / 日语翻译审校
我的翻译是字面对齐，本地 native speaker 审校能改出更地道文案

### E. Registry HTML 分支的 Markdown fallback 退出
ADR-M5-1 说 NSAttributedString 渲染不行可回退 WKWebView — 目前未观察到不行，不做

### F. MenuBarExtra 加 "最近安装 5 个 skill" 列表

### G. `Domain/` 抽 SwiftPM package（ADR-M6-1 延后的 refactor）
M6-A 场景：extension 和 app 共享更多代码时有收益。目前 extension 只需 parser，收益低

### H. 其他你想到的

---

## 操作要求（给接手的新 session）

- **默认中文回复**（技术名词英文）
- **Plan-driven**：大任务先写 plan 征求确认
- **TDD 严格**：失败测试 → 确认失败 → 实现 → 确认通过 → commit
- **Conventional Commits**；**禁止 `Co-Authored-By:` trailer**
- **原子写铁律**：先 `.tmp` + `FileManager.replaceItemAt`
- **不 mock fs / git / Keychain**，仅 URLProtocol 做网络桩
- **Swift 6 strict concurrency 必须过**
- **swift-format lint 必须静默**（四目录：App / Domain / Tests / SkillportPreview）
- **`./Scripts/check-parser-parity.sh` 必须通过**
- **新语法先查 Swift 6.0 兼容**；CI 是 canary

接手时请先读：
1. `/Users/crazy/own_project/skillport/CLAUDE.md`
2. spec `specs/2026-05-02-skillport-native-rewrite-design.md`
3. `git log --oneline | head -120`
4. `docs/RELEASE-SETUP.md` (了解发布流程)
5. 本 handoff 的 ADR + 踩坑两段
