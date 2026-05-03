# Skillport Release Setup

本文档列出首次发布 Skillport 前需要你（repo owner）做的一次性动作。完成 6 个步骤后即可跑 `./Scripts/release.sh X.Y.Z` 进入正式发布流程。

---

## 1. Apple Developer ID 证书

1. 在 https://developer.apple.com 开通 / 续费 Apple Developer Program（$99/年）
2. 在 Keychain Access.app 里生成 CSR（Certificate Signing Request），在开发者后台换两张证书：
   - **Developer ID Application** — 用于签 `.app`
   - **Developer ID Installer** — （可选，`.pkg` 会用到）
3. 把两张证书导入本机 Login Keychain，双击安装即可
4. 记下 **Team ID**（10 字符，如 `ABCDE12345`）。填到 `project.yml` 的 settings：

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "ABCDE12345"
```

下次跑 `./Scripts/generate-project.sh` 会把 team ID 落到 Xcode project。

---

## 2. Notarize credential

1. 在 https://appleid.apple.com → Security → App-Specific Passwords 生成一个 "skillport-notarize"，记下这个 password
2. 本机存到 Keychain 便于 release.sh 反复用：

```bash
xcrun notarytool store-credentials "skillport-notarize" \
    --apple-id you@example.com \
    --team-id ABCDE12345 \
    --password YOUR_APP_SPECIFIC_PASSWORD
```

3. 本地发布时：

```bash
export AC_PROFILE=skillport-notarize
./Scripts/notarize.sh build/export-0.1.0/Skillport.app
```

4. CI（GitHub Actions）不走 `AC_PROFILE`，需要 3 个 secret：`AC_USERNAME` / `AC_TEAM_ID` / `AC_APP_SPECIFIC_PASSWORD`（见步骤 5）

---

## 3. Sparkle EdDSA key pair

一次性生成，保管好 private key — 丢了所有旧 appcast signature 都作废。

```bash
# Sparkle 通过 SPM 引入后, 它的 artifact 会有 sign_update 工具
# 在 Xcode build 完一次之后, 工具通常在:
#   ~/Library/Developer/Xcode/DerivedData/Skillport-*/SourcePackages/artifacts/Sparkle/bin/

# 生成密钥对:
generate_keys  # 或者写全路径
# 输出: sparkle_eddsa_priv.key 和 sparkle_eddsa_pub.key
```

- **Private key** (`sparkle_eddsa_priv.key`): 保管好。`.gitignore` 已经屏蔽 `sparkle_eddsa_private_key` 和 `*.ed25519`，但仍然不要放项目目录
- **Public key**（base64 string）：填到 `App/Resources/Info.plist` 的 `SUPublicEDKey` 替换掉占位符 `YOUR_PUBLIC_ED25519_KEY_BASE64`
- CI secret: `SPARKLE_PRIVATE_KEY_BASE64` = private key 文件内容的 base64，例如：

```bash
base64 < sparkle_eddsa_priv.key | pbcopy
# 粘贴到 GitHub secret
```

---

## 4. Appcast 托管

选一条路：

### 4a. GitHub Pages（推荐，免费）

1. 在本仓库 Settings → Pages，选 `main` 分支 + `/docs` 或 `gh-pages` 分支作为 source
2. `appcast.xml` 的 feed URL：`https://crazygang-ai.github.io/skillport/appcast.xml`
3. DMG 下载走 GitHub Release（`release.yml` 里 `action-gh-release` 已经配）
4. `APPCAST_DMG_BASE_URL` 设为 release asset URL：
   `https://github.com/crazygang-ai/skillport/releases/download/v0.1.0`
   （每次发布 release.sh 会 tag vX.Y.Z，CI 自动 upload 到该 tag 的 release）
5. 把 `App/Resources/Info.plist` 的 `SUFeedURL` 改为：
   `https://crazygang-ai.github.io/skillport/appcast.xml`
6. 每次 release 后手动把 `build/export-X.Y.Z/appcast.xml` 拷到 Pages 源分支的对应路径并 push，Pages 自动部署

### 4b. 自有域名 / CDN

1. 域名如 `updates.crazygang.ai`，DNS 指到 S3 / Cloudflare Pages / 自家 nginx
2. `SUFeedURL` = `https://updates.crazygang.ai/appcast.xml`
3. `APPCAST_DMG_BASE_URL` = `https://updates.crazygang.ai`（DMG 放同域下）
4. 每次 release 后把 appcast.xml + DMG 一起上传到该域名

---

## 5. GitHub Secrets（CI 用）

在 repo 的 Settings → Secrets and variables → Actions 加这 8 个：

| Secret | 值 | 备注 |
|---|---|---|
| `DEVELOPMENT_TEAM` | Apple Team ID (10 字符) | 同步 `project.yml` |
| `DEV_ID_CERT_BASE64` | Developer ID Application `.p12` 的 base64 | `base64 < cert.p12` |
| `DEV_ID_CERT_PASSWORD` | `.p12` 导出时设的密码 | |
| `AC_USERNAME` | 你的 Apple ID | |
| `AC_TEAM_ID` | Apple Team ID | 同 `DEVELOPMENT_TEAM` |
| `AC_APP_SPECIFIC_PASSWORD` | App-Specific Password | 步骤 2 的那个 |
| `SPARKLE_PRIVATE_KEY_BASE64` | EdDSA private key 文件的 base64 | 步骤 3 生成 |
| `APPCAST_DMG_BASE_URL` | DMG 的 URL prefix | 步骤 4 决定 |

---

## 6. 第一次 release（端到端）

```bash
# 0. 确保 Info.plist 的 SUFeedURL 和 SUPublicEDKey 已替换成真实值
grep -E "YOUR_DOMAIN|YOUR_PUBLIC" App/Resources/Info.plist
# 如果有输出, 说明还没配好 — 改完再跑下面

# 1. 本地 build + archive + export
./Scripts/release.sh 0.1.0

# 2. Notarize (AC_PROFILE 已经 store 过)
export AC_PROFILE=skillport-notarize
./Scripts/notarize.sh build/export-0.1.0/Skillport.app

# 3. Package + sign + appcast
export SPARKLE_PRIVATE_KEY_PATH=$HOME/.ssh/sparkle_eddsa_priv.key  # 或实际路径
export APPCAST_DMG_BASE_URL=https://github.com/crazygang-ai/skillport/releases/download/v0.1.0
./Scripts/publish-appcast.sh build/export-0.1.0 0.1.0

# 4. Push tag → CI release workflow 会重跑一次（跳过已做的 notarize，只负责 GH Release upload）
git push && git push --tags
```

CI release workflow 读 secrets 把一切做一遍 — 首次建议本地做完验证 artifact，再推 tag 让 CI 重做（结果一致即 green light）。

---

## 后续 releases

```bash
# 确认 working tree clean 后
./Scripts/release.sh 0.1.1
./Scripts/notarize.sh build/export-0.1.1/Skillport.app
./Scripts/publish-appcast.sh build/export-0.1.1 0.1.1
git push && git push --tags
# 或者只推 tag, 让 CI 全自动
```

---

## 常见问题

**"signing identity not found"** — 检查 Keychain 里证书是否 imported，cert 是否过期（`security find-identity -v -p codesigning`）。

**notarize 失败 "invalid credentials"** — 确认 `AC_PROFILE` 对应的 credential 还有效（Apple 会每 180 天过期 App-Specific Password，重新生成即可）。

**Sparkle "signature mismatch"** — private key 和 Info.plist 的 public key 不配对。重新跑 `generate_keys` 或找回原私钥。

**GitHub Actions release workflow 跑失败但本地成功** — 多半是 secret 没配齐。Workflow 里所有 secret 读取都有清晰 error message。
