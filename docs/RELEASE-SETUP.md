# Skillport Release Setup

当前默认发布路径是：GitHub Actions 构建 ad-hoc signed `.app`，打包 `.dmg`，上传到 GitHub Release。这个路径不需要 Apple Developer ID、不做 notarization、不生成 Sparkle appcast。

这足够用于早期下载试用。代价是 macOS 首次打开时会提示 app 来自未识别开发者，用户需要在 System Settings -> Privacy & Security 里手动允许打开。

---

## 1. 默认发布：GitHub Release DMG

本仓库的 `.github/workflows/release.yml` 在推送 `v*` tag 时自动执行：

1. `./Scripts/bootstrap.sh`
2. `./Scripts/generate-project.sh`
3. `./Scripts/check-parser-parity.sh`
4. `swift-format lint --recursive App Domain Tests SkillportPreview`
5. `xcodebuild test`
6. `xcodebuild build` with ad-hoc signing
7. `./Scripts/package-dmg.sh`
8. upload `Skillport-X.Y.Z.dmg` to GitHub Release

默认路径不需要任何 GitHub Actions secrets。

---

## 2. 本地准备 release

确认 working tree clean 后：

```bash
./Scripts/release.sh 0.1.0
```

这个脚本会：

1. bump `project.yml` / generated Xcode project version
2. run parity / lint / tests
3. build Release `.app` with ad-hoc signing
4. package `build/export-0.1.0/Skillport-0.1.0.dmg`
5. commit version bump
6. create tag `v0.1.0`

然后 push：

```bash
git push && git push --tags
```

CI 会在 GitHub Release 里上传同版本 DMG。

---

## 3. 只让 CI 发布

如果不想本地打 DMG，也可以手动更新版本、commit，然后打 tag：

```bash
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

更推荐用 `./Scripts/release.sh X.Y.Z`，因为它会先跑本地校验并保持 app 内版本和 tag 一致。

---

## 4. 用户安装说明

下载 GitHub Release 里的 `Skillport-X.Y.Z.dmg` 后：

1. 打开 DMG
2. 把 `Skillport.app` 拖到 `Applications`
3. 首次打开如果被 macOS 拦截，进入 System Settings -> Privacy & Security，点击允许打开

这是未 notarized build 的预期行为。

---

## 5. 后续补齐正式分发能力

公开分发给普通用户前，再补：

1. Apple Developer Program
2. Developer ID Application certificate
3. notarization credential
4. Sparkle EdDSA key pair
5. `SUFeedURL` / `SUPublicEDKey`
6. appcast generation and signing

相关脚本仍保留：

- `Scripts/notarize.sh`
- `Scripts/publish-appcast.sh`
- `Scripts/prepare-export-options.sh`

后续恢复完整 signed/notarized/Sparkle 发布链路时，再把这些脚本接回 `release.yml`。

---

## 常见问题

**macOS 提示 app 来自未识别开发者** - 当前 DMG 是 ad-hoc signed 且未 notarized，这是预期行为。进入 System Settings -> Privacy & Security 手动允许打开。

**GitHub Actions 没有上传 DMG** - 检查 repo Actions permission。`release.yml` 已显式声明 `permissions: contents: write`，正常情况下可以上传 release asset。

**想取消首次打开警告** - 需要 Apple Developer ID + notarization。仅改 DMG 打包方式不能消除 Gatekeeper 警告。
