# Viabar 本机发布

## 首次准备

安装并登录 GitHub CLI：

```bash
brew install gh
gh auth login
```

Sparkle EdDSA 密钥已经通过下面的命令保存在本机登录钥匙串中：

```bash
./scripts/bootstrap-sparkle.sh
```

私钥不得提交到 Git。公钥已经写入 Viabar Target 的 `SUPublicEDKey`。

## 发布新版本

确认源码已经提交，并确认相邻公开仓库没有未提交改动：

```bash
git status --short
git -C ../Viabar-Releases status --short
```

发布新版本：

```bash
./scripts/release.sh 1.0.7 "更新说明"
```

现有公开仓库曾手工上传 `v1.0.6`，但 appcast 尚未记录该版本。首次发布带签名的 `1.0.7` 时，需要显式指定内部 build `8`：

```bash
RELEASE_BUILD_NUMBER=8 ./scripts/release.sh 1.0.7 "更新说明"
```

从下一版开始恢复普通命令，脚本会根据 appcast 自动递增内部 build number。

脚本会自动：

1. 计算下一个内部 build number。
2. 使用传入版本号归档 Viabar。
3. 生成本机留档 `dist/Viabar-1.0.7.dmg`，并复制为待上传的 `dist/Viabar.dmg`。
4. 使用钥匙串中的 Sparkle EdDSA 私钥签名待上传的 `Viabar.dmg`。
5. 在 `tyrival/Viabar-Releases` 创建 GitHub Release，并以固定文件名 `Viabar.dmg` 上传。
6. 将签名后的新版本插入公开仓库 `appcast.xml` 首项。
7. 提交并推送公开仓库中的 `appcast.xml`。

App 内 Sparkle 会根据 `appcast.xml` 中当前版本对应的地址下载更新，例如：

```text
https://github.com/tyrival/Viabar-Releases/releases/download/v1.0.7/Viabar.dmg
```

官网可以始终使用不带版本号的最新版下载地址：

```text
https://github.com/tyrival/Viabar-Releases/releases/latest/download/Viabar.dmg
```

## 发布脚本长时间没有响应

脚本会在每个可能等待的步骤前输出 `==> ...`。如果长时间没有新输出，最后一行阶段日志就是当前停留的位置。例如：

```text
==> Syncing public release repository
```

表示正在执行公开仓库的 `git pull --ff-only`。网络不稳定时可以按 `Ctrl+C` 结束，稍后重新执行发布命令。脚本会在 GitHub Release 或 appcast 已存在对应版本时停止，不会重复发布同一个版本。

## 当前公开仓库的本地改动

首次使用发布脚本前，需要人工处理相邻目录 `../Viabar-Releases` 中已有的本地修改。脚本检测到公开仓库不干净时会停止，避免覆盖官网或手工维护的 appcast。

查看改动：

```bash
git -C ../Viabar-Releases status --short
git -C ../Viabar-Releases diff -- appcast.xml
```

确认改动有价值时提交；确认不需要时再自行还原。`.idea/` 是 IDE 本机目录，建议加入公开仓库自己的 `.gitignore`。

## 没有 Developer ID 时的限制

当前流程使用 Sparkle EdDSA 验证更新包来源，但没有 Apple Developer ID 签名和公证。首次下载安装可能仍需在 macOS 中手动确认打开。后续可在加入 Apple Developer Program 后补充正式签名和公证流程。
