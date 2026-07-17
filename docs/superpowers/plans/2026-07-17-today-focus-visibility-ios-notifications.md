# 今日推荐显示开关与 iOS 系统通知实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 macOS 和 iOS 增加各自本地保存的今日推荐显示开关，并让共享系统通知调度在 iOS 生命周期下工作。

**Architecture:** 使用共享 `UserDefaults` store 表达今日推荐可见性，两端设置页绑定该值、总览按值条件渲染。通知调度核心移除无条件 `AppKit` 依赖，macOS 保留唤醒监听，iOS 由 `scenePhase` 激活事件触发 reconciliation。

**Tech Stack:** Swift 5.10+、SwiftUI、UserDefaults、UserNotifications、SwiftData、macOS 14+、iOS 17+

## Global Constraints

- 两个平台各自保存开关状态，不跨设备同步。
- 默认开启，不改变现有用户升级后的总览显示。
- 不修改 SwiftData schema、备份结构或 CloudKit 配置。
- 不改变今日推荐算法及已确认的通知补发语义。
- 直接在 `main` 工作区修改，不提交。
- 未经用户明确要求，不编译或运行测试。

---

### Task 1: 今日推荐本地设置存储

**Files:**
- Modify: `Viabar/Models/AppSettings.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Produces: `TodayFocusVisibilitySettingsStore.isVisible(defaults:) -> Bool`
- Produces: `TodayFocusVisibilitySettingsStore.setVisible(_:defaults:)`

- [x] 增加默认开启、写入关闭、重新开启三个断言的 store 测试。
- [x] 增加只负责 UserDefaults 读写的共享 store，缺少 key 时返回 `true`。
- [x] 静态核对测试使用独立 suite，不污染真实偏好。

### Task 2: macOS 设置与总览接入

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/ContentView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `TodayFocusVisibilitySettingsStore`

- [x] 在“视图”组首行增加“今日推荐”Switch，并在变化时写入本地设置。
- [x] 总览读取可见性状态，仅在开启时构造并显示 `TodayFocusSectionView`。
- [x] 核对英文和简体中文本地化键值已存在。

### Task 3: iOS 设置与总览接入

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentSettingsView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `ViabariOS/en.lproj/Localizable.strings`
- Modify: `ViabariOS/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `TodayFocusVisibilitySettingsStore`

- [x] 在 iOS“显示”Section 增加“今日推荐”Toggle。
- [x] iOS 总览仅在开关开启时显示推荐区域。
- [x] 核对 iOS 英文和简体中文本地化已存在。

### Task 4: 通知服务跨平台生命周期解耦

**Files:**
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Modify: `Viabar/ViabarApp.swift`
- Modify: `ViabariOS/ViabariOSApp.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: `NotificationScheduleService.reconcile()` 或现有等价公开入口
- Preserves: 稳定通知标识、独立提醒调度、完成撤销、最近错过一条

- [x] 将 `AppKit` import、`NSWorkspace` observer 和 macOS 激活监听限定到 macOS。
- [x] 保持 macOS 唤醒后的 reconciliation 行为。
- [x] 在 iOS 根场景监听 `scenePhase`，进入 `.active` 后调用 reconciliation。
- [x] 增加静态逻辑与回归测试，保证重复激活不会重复补发，且全局只补最近错过的一条。

### Task 5: 静态验证

**Files:**
- Inspect all files modified by Tasks 1-4.

- [x] 运行 `git diff --check`，无输出、退出码 0。
- [x] 运行四份本地化文件的 `plutil -lint`，全部 `OK`。
- [x] 使用 `rg` 确认 `AppKit`/`NSWorkspace` 位于 `#if os(macOS)` 编译路径。
- [x] 检查 `git diff`，未新增或修改 SwiftData schema 声明。
- [x] 未运行 `xcodebuild` 或测试命令。
