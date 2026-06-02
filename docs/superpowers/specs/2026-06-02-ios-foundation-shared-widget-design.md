# iOS Foundation And Shared Widget Design

## 目标

在现有 `Viabar.xcodeproj` 中增加 iOS 基础骨架，并保持 macOS 现有行为不变。

第一阶段交付：

1. iOS App 使用独立 App Group 打开本机 SwiftData 主库。
2. iOS Widget 使用同一 iOS App Group 读取主库。
3. iOS Widget 复用现有 macOS Widget 的 Medium / Large 布局、项目选择、任务勾选、刷新和深链语义。
4. iOS 主界面暂时保留简单占位，不实现完整移动端功能。
5. 不启用 CloudKit，不修改 SwiftData schema，不迁移或删除任何用户数据库。

## 已确认边界

最低系统版本：

```text
macOS App + Widget    macOS 15.6+
iOS App + Widget      iOS 17.6+
```

本地数据边界：

```text
macOS App + macOS Widget
└── group.com.tyrival.Viabar

iOS App + iOS Widget
└── group.com.tyrival.ViabariOS
```

App Group 只负责同一设备上的 App 与 Widget 共享。第一阶段 Mac 与 iPhone 不同步。恢复 Apple Developer Program 后，再通过单独设计的 CloudKit Container 和迁移方案实现双端同步。

## 工程结构

保留现有 macOS Target：

```text
Viabar
ViabarWidgetExtension
```

新增 iOS Target：

```text
ViabariOS
ViabariOSWidgetExtension
```

iOS Widget 源码目录从 Xcode 默认生成的：

```text
ViabariOSWidgetExtension/
```

重命名为：

```text
ViabariOSWidget/
```

Target 和扩展产物仍保持：

```text
ViabariOSWidgetExtension
ViabariOSWidgetExtension.appex
```

Bundle Identifier 使用：

```text
ViabariOS                     com.tyrival.ViabariOS
ViabariOSWidgetExtension      com.tyrival.ViabariOS.Widget
```

## 共享代码策略

### 原则

Widget 扩展产物分开，业务实现尽量共用。

两个平台必须保留独立 `.appex`，因为它们由不同 App 嵌入，并且使用不同平台、本地 App Group、签名和 entitlement。不得尝试让 iOS App 直接嵌入 macOS Widget 产物。

### 共用范围

优先复用现有实现：

- `WidgetContent`
- `WidgetContentBuilder`
- `SelectWidgetProjectIntent`
- `WidgetProjectEntity`
- `WidgetProjectEntityQuery`
- `ToggleWidgetTaskIntent`
- `RefreshWidgetIntent`
- `ViabarWidgetProvider`
- Medium / Large Widget 视图
- 任务完成语义
- 提醒状态色
- 深链路由语义
- 双语 Widget 文案

不为 iOS Widget 新建第二套内容模型、项目查询、任务完成逻辑或视图树。

### 平台适配层

共享代码不得硬编码 macOS App Group。新增窄适配入口，根据编译平台返回本地 App Group：

```text
macOS    group.com.tyrival.Viabar
iOS      group.com.tyrival.ViabariOS
```

SwiftData schema 继续由同一份 `SharedModelContainer.schema` 管理。第一阶段不得新增、删除或修改任何持久化实体、字段、关系或 delete rule。

如 Widget 深链 URL 的宿主 App 入口需要平台差异，差异应集中在 URL 路由适配层，不复制 Widget 视图。

## iOS App 骨架

iOS App 第一阶段只承担：

1. 使用 iOS App Group 创建本机共享库目录。
2. 打开与 Widget 一致的 SwiftData 主库。
3. 确保默认设置记录存在。
4. 注入 `ModelContainer`。
5. 显示简单占位页，说明 iOS 基础骨架已接入。
6. 接收 Widget 深链，预留后续项目导航入口。

第一阶段不把 macOS `ContentView`、`MenuBarExtra`、Sparkle、AppKit 窗口逻辑或 macOS Settings UI 直接加入 iOS Target。

## iOS Widget 骨架

iOS Widget 与 macOS Widget 保持相同的两个稳定 kind：

```text
ViabarMediumWidget
ViabarLargeWidget
```

两端 Widget 均支持：

- 选择活跃项目
- Medium / Large 两种尺寸
- 展示项目标题、进度和任务
- 完成任务
- 手动刷新
- 点击项目、里程碑或子任务后打开宿主 App

空间差异继续只由现有 row budget 和 SwiftUI 自适应布局处理。若 iOS 实机出现排版差异，再增加窄范围的平台布局适配，不预先复制视图。

## Entitlements

第一阶段新增：

```text
ViabariOS/ViabariOS.entitlements
ViabariOSWidget/ViabariOSWidget.entitlements
```

两者都只声明：

```text
group.com.tyrival.ViabariOS
```

现有 macOS entitlements 保持：

```text
group.com.tyrival.Viabar
```

第一阶段不得新增 iCloud 或 CloudKit entitlement。

## CloudKit 预留

当前主库和回收站容器继续显式使用：

```swift
cloudKitDatabase: .none
```

启用 iCloud 前必须单独设计：

1. CloudKit Container 标识。
2. 双端 schema 契约和版本化迁移。
3. macOS 现有 App Group 主库升级路径。
4. iOS 本地主库升级路径。
5. `trash.store` 是否参与云同步。
6. `AppSettings` 中本地专属设置与同步设置的拆分。
7. 备份格式兼容与恢复后的迁移。
8. 远程变更后的 Widget 刷新策略。

## 实施顺序

1. 将目录 `ViabariOSWidgetExtension/` 改为 `ViabariOSWidget/`，同步修改工程路径。
2. 将 iOS Widget bundle identifier 改为 `com.tyrival.ViabariOS.Widget`。
3. 为 iOS App 与 iOS Widget 增加 App Group entitlements。
4. 把共享容器入口改为平台感知，但保持 macOS 现有路径不变。
5. 让 iOS App 接入共享本地库并保留占位主界面。
6. 让 iOS Widget Target 复用 macOS Widget 所需共享文件。
7. 移除 Xcode 模板 Widget 占位实现，接入现有 Medium / Large Widget。
8. 执行静态检查并交由用户在 Xcode 中编译、运行和手测。

## 静态验证

实现后至少执行：

```bash
rg -n "@Model|Schema\\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift'
rg -n "default\\.store|trash\\.store|ViabarSharedStore|cloudKitDatabase|group\\.com\\.tyrival" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift' --glob '*.entitlements'
rg -n "ViabariOSWidgetExtensionExtension|ViabariOSWidgetExtension/" Viabar.xcodeproj ViabariOSWidget
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
plutil -lint Viabar/Viabar.entitlements ViabarWidget/ViabarWidget.entitlements
plutil -lint ViabariOS/ViabariOS.entitlements ViabariOSWidget/ViabariOSWidget.entitlements
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

负向 `rg` 无命中属于成功条件。

## 用户手测

用户在 Xcode 中完成编译与运行验证：

1. 运行现有 macOS App，确认主窗口、菜单栏组件和现有桌面 Widget 行为不变。
2. 运行 iOS App，确认占位页可打开，且本地 SwiftData 容器创建成功。
3. 在 iOS 模拟器或设备添加 Medium 和 Large Widget。
4. 确认两个尺寸均可选择活跃项目。
5. 确认项目标题、进度、任务列表和剩余任务数显示正常。
6. 确认勾选任务后 Widget 更新。
7. 确认刷新按钮有效。
8. 确认点击项目、里程碑和子任务后可唤起 iOS App。
9. 确认 Mac 与 iPhone 第一阶段不会错误地共享本地库或自动同步。

## 非目标

- 不启用 iCloud 或 CloudKit。
- 不修改 SwiftData schema。
- 不实现数据库迁移框架。
- 不删除、覆盖或重建任何现有数据库。
- 不实现完整 iOS 项目列表、详情页、搜索、提醒、设置或备份 UI。
- 不重构 macOS 主界面。
- 不引入第三方依赖。
