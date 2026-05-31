# Viabar 本机 Sparkle 发布流程设计

## 目标

为 Viabar 建立一条可重复执行的本机发布流程。开发者只需输入新版本号和更新说明，脚本即可完成 Release 归档、DMG 打包、Sparkle EdDSA 签名、GitHub Release 上传以及公开 `appcast.xml` 更新。

同时清理私有源码仓库中已经被 Git 跟踪的本地生成物，避免继续提交 Xcode 缓存、归档和本机工具状态。

## 约束

- 当前没有 Apple Developer Program 账号，也没有 `Developer ID Application` 证书。
- 发布流程用于自用或小范围分发，不承诺通过 Apple 公证。
- 首次下载安装仍可能触发 macOS 安全提示，需要用户手动确认。
- Sparkle EdDSA 签名必须启用，用于验证后续更新包确实来自 Viabar 发布者。
- 公开仓库使用 `tyrival/Viabar-Releases`。该仓库可重建，但当前保留已有官网源码。
- 发布在开发者本机执行，不在 GitHub Actions 中保存 Sparkle 私钥。

## 当前问题

### Sparkle 配置存在分叉

当前项目同时存在多套 feed 配置：

- Xcode 生成 Info.plist 的 `INFOPLIST_KEY_SUFeedURL` 指向 GitHub Releases Atom。
- `UpdateService.swift` 运行时调用 `setFeedURL` 指向公开仓库中的 `appcast.xml`。
- 本地未跟踪的 `Viabar/Info.plist` 也包含 `appcast.xml` 地址，但主 Target 当前不使用该文件。

Sparkle 官方建议静态 feed 使用 Info.plist 的 `SUFeedURL`，不建议用 `setFeedURL` 持久覆盖静态地址。

### 现有 appcast 无签名

公开 `appcast.xml` 已包含历史版本，但 enclosure 没有 `sparkle:edSignature`。这不足以验证下载的更新包是否可信。

### 沙盒自动安装配置不完整

Viabar 开启 App Sandbox。Sparkle 的沙盒应用需要启用 Installer Launcher XPC，并在应用 entitlements 中添加 Installer 通信所需的 mach lookup 临时例外。Viabar 已有 `com.apple.security.network.client`，因此无需启用 Downloader XPC。

### 发布步骤容易遗漏

现有 GitHub Actions workflow：

- 发布目标写成了不存在的 `tyrival/Viabar-Release`，实际仓库名为 `tyrival/Viabar-Releases`。
- 输入的版本号没有传递给 Xcode。
- 没有生成 Sparkle EdDSA 签名。
- 没有更新 `appcast.xml`。
- 归档、上传和 XML 更新仍然割裂。

### 仓库包含本地生成物

私有仓库已跟踪：

- `build/`：约 742 MB，本地统计为 2329 个 Git 已跟踪文件。
- `.superpowers/brainstorm/`：本地设计预览和进程状态。
- `.claude/settings.local.json`：本机工具配置。

## 方案

### Sparkle 配置收敛

主应用使用 Xcode 生成的 Info.plist，统一添加：

- `SUFeedURL=https://raw.githubusercontent.com/tyrival/Viabar-Releases/main/appcast.xml`
- `SUPublicEDKey=<bootstrap 脚本生成的 EdDSA 公钥>`
- `SUEnableAutomaticChecks=YES`
- `SUEnableInstallerLauncherService=YES`

`UpdateService.swift` 不再调用 `setFeedURL`。为迁移已经运行过旧版本的用户，在 updater 启动后调用 Sparkle 提供的 API 清理旧的 feed URL UserDefaults 覆盖值。

`Viabar.entitlements` 添加：

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
</array>
```

### Sparkle 密钥初始化

新增 `scripts/bootstrap-sparkle.sh`：

1. 定位 Xcode Swift Package Manager 下载的 Sparkle `generate_keys`。
2. 执行 `generate_keys`。
3. 将私钥保留在本机登录钥匙串。
4. 输出需要写入 Xcode 配置的 `SUPublicEDKey`。
5. 输出后续执行发布脚本的命令。

初始化脚本只需执行一次。私钥不得写入 Git、公开仓库或 GitHub Secrets。

### 本机发布脚本

新增 `scripts/release.sh`，调用方式：

```bash
./scripts/release.sh 1.0.7 "更新说明"
```

脚本执行：

1. 校验版本号格式为 `X.Y.Z`。
2. 检查 `gh` 已安装并且已经登录。
3. 定位 Sparkle `sign_update`。
4. 从公开 `appcast.xml` 读取当前最高内部 build number，自动加一。
5. 使用命令行参数向 `xcodebuild archive` 传入：
   - `MARKETING_VERSION=<输入版本号>`
   - `CURRENT_PROJECT_VERSION=<自动计算的 build number>`
   - 不覆盖 `MACOSX_DEPLOYMENT_TARGET`，沿用 Xcode Release 配置。
6. 从 archive 复制 `Viabar.app`，制作 `Viabar-<版本号>.dmg`。
7. 调用 Sparkle `sign_update` 生成 `sparkle:edSignature` 和包长度。
8. 使用 `gh release create` 在 `tyrival/Viabar-Releases` 创建 `v<版本号>` Release 并上传 DMG。
9. 使用结构化 XML 更新脚本在公开仓库 `appcast.xml` 顶部插入新 `<item>`：
   - `title`
   - `sparkle:version`
   - `sparkle:shortVersionString`
   - `sparkle:minimumSystemVersion`，从 Xcode Release 配置读取
   - `description`
   - enclosure 下载地址
   - `sparkle:edSignature`
   - 文件长度
10. 提交并推送公开仓库中的 `appcast.xml`。
11. 输出 Release 下载地址与 appcast 地址。

发布脚本使用相邻目录 `../Viabar-Releases` 作为公开仓库工作副本；目录不存在时自动克隆。脚本只修改根目录 `appcast.xml`，不改动官网源码。

### XML 更新脚本

新增 `scripts/update_appcast.py`，职责保持单一：

- 使用 XML 解析器读取 appcast。
- 检查新 build number 必须大于已有版本。
- 检查新版本号尚未存在。
- 将新版本插入 `<channel>` 的第一个 `<item>`。
- 保留历史版本。
- 写回 UTF-8 XML。

Shell 脚本只负责流程编排，不通过字符串拼接直接编辑 XML。

### 仓库清理

更新 `.gitignore`，加入：

```gitignore
build/
DerivedData/
dist/
*.dmg
*.xcarchive/
.superpowers/brainstorm/
.claude/settings.local.json
.worktrees/
```

从 Git 索引中移除但保留本地文件：

```bash
git rm -r --cached build .superpowers/brainstorm
git rm --cached .claude/settings.local.json
```

保留：

- `docs/superpowers/`
- `.github/workflows/`
- `Viabar.xcodeproj/xcshareddata/xcschemes/`
- `Viabar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

普通提交并推送后，GitHub 默认分支的文件列表中不再显示这些本地生成物。若未来还需要缩小 Git 历史体积，再单独执行历史重写；本次不做强制推送。

## 错误处理

发布脚本遇到以下情况时立即退出并给出修复提示：

- 未安装 `gh`。
- `gh` 尚未登录。
- Sparkle 工具不存在。
- Sparkle 私钥尚未初始化。
- 版本号格式错误。
- 新版本或 Git tag 已存在。
- 公开仓库存在未提交更改。
- DMG 打包失败。
- Sparkle 签名失败。
- GitHub Release 上传失败。
- appcast XML 不合法。
- 公开仓库提交或推送失败。

发布 Release 成功但 appcast 推送失败时，脚本必须明确提示：DMG 已上传，但用户端暂时不会收到更新，需要修复公开仓库后重新运行 XML 更新步骤。

## 验证

静态验证：

- 检查 Xcode 生成 Info.plist 的 Sparkle keys。
- 检查应用 entitlements 包含 Installer Launcher XPC 通信例外。
- 检查 `UpdateService.swift` 不再调用 `setFeedURL`。
- 检查 `.gitignore` 覆盖所有本地生成物。
- 检查 Git 索引中不再包含清理目标。

脚本验证：

- 使用临时 XML fixture 测试 `scripts/update_appcast.py` 插入新版本。
- 测试重复版本、倒退 build number 和非法 XML 均会失败。
- 在没有 `gh` 的环境下运行发布脚本，确认给出安装提示。

手工端到端验证：

1. 执行 `scripts/bootstrap-sparkle.sh`。
2. 将公钥写入项目后构建一次旧版本 App。
3. 执行 `scripts/release.sh <新版本> "<更新说明>"`。
4. 确认 GitHub Release 包含新 DMG。
5. 确认公开 `appcast.xml` 首项包含新版本、内部 build number 和 `sparkle:edSignature`。
6. 在旧版本 App 中点击“检查更新”，确认能发现、下载并安装新版本。

## 不在本次范围内

- Apple Developer ID 签名。
- Apple notarization 和 stapling。
- GitHub Actions 自动发布。
- Sparkle delta 更新。
- 私有源码仓库历史重写。
- 官网前端重构。
