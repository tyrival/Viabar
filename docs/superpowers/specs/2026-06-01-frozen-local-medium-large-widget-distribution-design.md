# Frozen Local Medium And Large Widget Distribution Design

## 目标

为 Viabar 增加一个 Medium 桌面 Widget，并保留现有 Large Widget。两种尺寸使用同一套项目选择、任务完成、刷新、深链跳转和 App Group 数据链路；Medium 仅减少可见任务行数。

在 Apple Developer Program 未续费、无法使用 Developer ID Application 和 notarization 的前提下，新增一条独立的 frozen-local 分发路径。该路径用于生成可手动安装到当前 Mac 或新 Mac 的冻结版 DMG，并验证 Widget Extension 的可控条件。

本设计不承诺 macOS 未公开的能力：App 不能强制把 Widget 自动添加到桌面，也不能强制系统立即重建 Widget 面板索引。

## 已确认边界

安装与注册的验收定义为：

1. 用户将 Viabar 拖入 `/Applications`。
2. 新电脑首次安装 ad hoc 包时，用户接受右键“打开”手动放行。
3. 用户首次启动 Viabar 一次，以初始化 App Group 共享库并让 macOS 发现 Widget Extension。
4. 系统 Widget 面板中可以找到 Viabar Medium 和 Large。
5. 用户自行从系统面板将所需 Widget 拖到桌面。
6. 若系统索引延迟，使用安全恢复脚本后重新登录或重启。

## 当前问题与设计约束

当前安装包使用 ad hoc 签名。现场排查确认：

- Widget Chrono 缓存清理后，旧 Medium 残留已消失；
- 共享数据库 `integrity_check` 正常；
- 项目选择查询可以返回活跃项目；
- macOS 可以生成带所选项目 UUID 的配置预览 timeline；
- 桌面实例仍可能保留空配置，继续显示“请选择项目”。

因此，现有 ad hoc 包的 Widget 配置持久化异常是 frozen-local 交付前的 blocker。实现完成后，必须在当前 Mac 上实际验证“选择项目后桌面实例更新”。只验证 DMG 可打开、扩展已嵌入或 timeline 预览已生成，不足以判定交付成功。

由于没有 Developer ID 和 notarization，frozen-local 包无法提供 Apple 官方信任链，也不能承诺任意 macOS 环境中的系统索引时序完全一致。脚本应验证所有可控条件，并为索引延迟提供安全恢复路径。

## Widget 结构

### 独立 Widget kind

保留现有 Large kind：

```text
ViabarLargeWidget
```

新增 Medium kind：

```text
ViabarMediumWidget
```

两个 kind 必须长期保持稳定。冻结分发后不再修改 kind 名称，避免破坏用户已添加的桌面实例。

### 共享逻辑

Medium 与 Large 共用：

- `SelectWidgetProjectIntent`
- `WidgetProjectEntity`
- `WidgetProjectEntityQuery`
- `ToggleWidgetTaskIntent`
- `RefreshWidgetIntent`
- `ViabarWidgetProvider`
- `WidgetContentBuilder`
- `SharedModelContainer.makeWidgetContainer()`
- App Group `group.com.tyrival.Viabar`
- 任务完成语义
- 提醒状态色
- 深链跳转

不得为 Medium 新建第二套持久化模型、项目选择逻辑或任务完成逻辑。

### 尺寸差异

Large：

- 仅声明 `.systemLarge`
- `rowBudget = 10`

Medium：

- 仅声明 `.systemMedium`
- `rowBudget = 3`
- 超过 3 行任务或子任务时，显示本地化的剩余未完成数量。

Medium 与 Large 的差异只限于空间适配和任务行预算。Medium 仍保留项目标题、进度、复选框、刷新按钮、提醒状态色和隐藏条目计数。空间不足时优先减少可见任务行，不删除核心交互。

### 系统面板呈现

`ViabarWidgetBundle` 同时暴露 `ViabarMediumWidget` 和 `ViabarLargeWidget`。系统 Widget 面板中应可以找到两种独立尺寸，用户可明确选择所需 Widget。

## Frozen-Local 分发路径

新增独立脚本：

```text
scripts/package_frozen_local.sh
```

该脚本不替代现有 Sparkle `scripts/release.sh`。两者职责必须分开：

- `release.sh`：保留未来恢复 Developer ID 后的正式发布方向；
- `package_frozen_local.sh`：生成无 Developer ID 条件下的本地冻结版 DMG。

### 产物

```text
dist/Viabar-<version>-frozen-local.dmg
```

DMG 内容：

```text
Viabar.app
Applications -> /Applications
```

### 打包步骤

脚本必须：

1. 使用 Release 配置归档 Viabar。
2. 在当前无有效 Developer ID 的条件下使用 ad hoc 签名。
3. 校验主 App 和 Widget Extension 均包含 App Group entitlement：

```text
group.com.tyrival.Viabar
```

4. 校验 App 内只嵌入一个 `ViabarWidgetExtension.appex`。
5. 校验扩展 bundle 暴露 `ViabarMediumWidget` 和 `ViabarLargeWidget` 两个 kind。
6. 对 App 执行：

```bash
codesign --verify --deep --strict
```

7. 创建包含 `/Applications` 快捷方式的 DMG。
8. 执行：

```bash
hdiutil verify
```

9. 只读挂载 DMG，检查 `Viabar.app` 和 `Applications` 快捷方式。
10. 输出安装说明与已知限制。

## 安全恢复脚本

新增：

```text
scripts/reset_local_widget_cache.sh
```

用途：

- 注销已知的 Viabar Debug 或安装版 Widget 扩展登记；
- 清理 Widget Chrono 缓存；
- 处理旧版本 Widget kind 残留；
- 为 macOS Widget 面板索引延迟提供恢复入口。

允许清理的缓存目录：

```text
~/Library/Containers/com.tyrival.Viabar.Widget/Data/SystemData/com.apple.chrono
```

禁止删除或修改：

```text
~/Library/Group Containers/group.com.tyrival.Viabar
~/Library/Group Containers/group.com.tyrival.Viabar/ViabarSharedStore/default.store
~/Library/Group Containers/group.com.tyrival.Viabar/ViabarSharedStore/trash.store
```

脚本必须在执行删除前打印目标路径，并明确说明不会触碰业务数据库。

## 安装说明

冻结版 DMG 应配套说明：

1. 将 `Viabar.app` 拖入 `/Applications`。
2. 首次安装时对 `/Applications/Viabar.app` 右键选择“打开”。
3. 启动 Viabar 一次。
4. 打开 macOS Widget 面板。
5. 将 Viabar Medium 或 Large 拖到桌面。
6. 右键 Widget，选择“编辑小组件”，再选择项目。
7. 若 Widget 面板未出现 Viabar 或仍显示旧版本，退出 Viabar，运行 `scripts/reset_local_widget_cache.sh`，然后重新登录或重启。

## 验证与验收

### 静态检查

- `ViabarMediumWidget` 和 `ViabarLargeWidget` 使用两个稳定 kind。
- 两者共用同一个项目选择 intent 和任务操作链路。
- Medium `rowBudget = 3`，超过预算时显示本地化的剩余未完成数量。
- Large `rowBudget = 10`。
- App 内仅嵌入一个 Widget Extension。
- 主 App 与 Widget Extension 的 App Group entitlement 一致。
- `git diff --check` 通过。
- `plutil -lint` 通过。

### 当前 Mac 人工验证

1. 使用恢复脚本清理旧 Widget 缓存。
2. 安装 frozen-local DMG。
3. 首次启动 Viabar。
4. 确认系统 Widget 面板出现 Medium 和 Large。
5. 分别拖出 Medium 和 Large。
6. 分别选择项目。
7. 确认选择项目后桌面实例立即更新，不再停留在“请选择项目”。
8. 确认两种尺寸均可显示任务、完成任务、刷新和深链打开主 App。
9. 确认 Large 显示更多任务；Medium 仅减少任务行，不改变任务完成语义。

### 新电脑验收

1. 拖入 `/Applications`。
2. 首次右键“打开”手动放行。
3. 启动 Viabar 一次。
4. 确认系统面板出现 Medium 和 Large。
5. 确认两个 Widget 均可选择项目并正常更新桌面实例。
6. 若系统索引延迟，运行恢复脚本后重新登录或重启。

## 非目标

- 不自动将 Widget 添加到桌面。
- 不尝试通过私有 API 强制刷新系统 Widget 面板索引。
- 不启用 CloudKit。
- 不修改 SwiftData schema。
- 不删除、重建或覆盖用户业务数据库。
- 不把 frozen-local 脚本伪装成正式 Developer ID 分发流程。
- 不承诺没有 Developer ID 和 notarization 时具备 Apple 官方信任链。
