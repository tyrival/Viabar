# Viabar iOS App 开发文档

## 1. 产品概述与双端互通

### 1.1 定位

Viabar iOS 是 macOS 桌面端 Viabar 的移动伴侣。它复用 macOS 端的核心数据模型和业务逻辑，通过 **iCloud + CloudKit** 实现双端数据秒级静默同步。iOS 端聚焦于**随时查看进度**、**快速记录备忘**和**接收提醒通知**，设计语言与 macOS 端保持一致。

### 1.2 双端互通机制

| 维度 | macOS 端 | iOS 端 |
|------|----------|--------|
| 数据持久化 | SwiftData + CloudKit (`iCloud.com.viabar`) | 同一 CloudKit Container，共享 Schema |
| 同步方式 | NSPersistentCloudKitContainer 自动同步 | 同一机制 |
| 通知推送 | UNUserNotificationCenter | 同一机制 + APNs Silent Push |
| 数据模型 | Project / Milestone / SubTask / Memo / Reminder / AppSettings | **完全复用**，零差异 |
| 业务服务 | ProjectService / NotificationScheduleService / BackupService | 复用 ProjectService / NotificationScheduleService，BackupService 简化 |

### 1.3 iOS 端功能范围（MVP）

基于 macOS 端已有的功能矩阵，iOS 端 MVP 聚焦以下模块：

1. **项目总览** — 以卡片网格展示所有活跃项目及其进度
2. **里程碑时间线** — 垂直时间线展示项目的里程碑与子任务
3. **备忘录** — 查看和追加项目备忘录
4. **全局搜索** — 模糊搜索所有项目/里程碑/子任务/备忘录，点击跳转并高亮
5. **提醒通知** — 基于 `NotificationScheduleService` 的本地通知，与 macOS 共用同一调度逻辑
6. **设置** — 主题（跟随系统/浅色/深色）、语言（中/英）、iCloud 同步开关
7. **Widget** — 桌面小组件展示项目进度（WidgetKit）

---

## 2. 技术栈约束

| 层级 | 技术选型 |
|------|----------|
| 语言 | Swift 5.10+ |
| UI 框架 | SwiftUI（完全遵循 Apple HIG iOS 版） |
| 数据持久化 | SwiftData |
| 多端同步 | iCloud + CloudKit（`iCloud.com.viabar` 私有数据库） |
| 系统集成 | WidgetKit（桌面组件）/ UNUserNotificationCenter |
| 最低版本 | iOS 17.0+ |
| 依赖管理 | 零第三方依赖，纯 Apple 原生框架 |

---

## 3. 统一数据结构定义（双端唯一真理源）

> **关键约束**: iCloud + CloudKit 同步要求双端的 SwiftData Schema **完全一致**。以下每一个属性名、类型、`@Attribute` 约束、`@Relationship` 及其 `deleteRule` 都是同步契约，两端不容许任何偏差。修改任何字段前必须在 macOS 端变更并同步到 iOS 端。

---

### 3.1 Reminder（提醒实体）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `reminderId` | `UUID` | — | 唯一标识 |
| `type` | `String` | — | `"single"` 或 `"repeating"` |
| `fireTime` | `String?` | — | 重复类型的时间，格式 `"HH:mm"` |
| `fireTimestamp` | `Date?` | — | 单次类型的绝对触发时间 |
| `repeatIntervalDays` | `Int?` | — | 重复间隔天数；`0`=每小时，`-1`=工作日，`30`=每月，`90`=每3月，`180`=每6月，`365`=每年 |
| `lastTriggeredTimestamp` | `Date?` | — | 上次触发时间戳 |

---

### 3.2 NotificationScheduleEntry（通知调度条目）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `entryId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `ownerId` | `UUID` | — | 所属实体的 ID（Project/Milestone/SubTask） |
| `ownerKind` | `String` | — | `"project"` / `"milestone"` / `"subtask"` |
| `projectId` | `UUID` | — | 关联项目 ID |
| `projectTitle` | `String` | — | 关联项目标题（冗余，用于通知文案） |
| `body` | `String` | — | 通知正文（里程碑/子任务标题或穿透文案） |
| `fireDate` | `Date` | — | 触发时间 |

---

### 3.3 Project（项目）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `projectId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `title` | `String` | — | 项目名称 |
| `hideCompleted` | `Bool` | — | 是否默认隐藏已完成里程碑 |
| `isArchived` | `Bool` | 默认 `false` | 是否已归档 |
| `isFavorite` | `Bool` | 默认 `false` | 是否星标收藏 |
| `orderIndex` | `Int` | 默认 `0` | 排序索引 |
| `archivedAt` | `Date?` | — | 归档时间 |
| `accentColor` | `String` | 默认 `"#0085ff"` | 主题色 Hex |
| `sfSymbolName` | `String` | 默认 `"circle.dashed"` | SF Symbol 图标名 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `milestones` | `[Milestone]` | `.cascade` | `Milestone.project` |
| `memos` | `[Memo]` | `.cascade` | `Memo.project` |
| `reminder` | `Reminder?` | `.cascade` | — |
| `archiveFolder` | `ArchiveFolder?` | `.nullify` | — |

**计算属性（不持久化，两端必须一致）**:

| 属性 | 返回类型 | 说明 |
|------|---------|------|
| `progress` | `Double` | Rollup 进度计算，四舍五入到 4 位小数 |
| `topUnfinishedTitle` | `String?` | 上下文穿透：第一个未完成任务标题 |
| `unfinishedMilestones` | `[Milestone]` | 未完成的里程碑，按 orderIndex 排序 |

---

### 3.4 Milestone（里程碑）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `milestoneId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `title` | `String` | — | 里程碑名称 |
| `isCompleted` | `Bool` | 默认 `false` | 是否完成 |
| `completedAt` | `Date?` | — | 完成时间 |
| `orderIndex` | `Int` | — | 排序索引 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `subtasks` | `[SubTask]` | `.cascade` | `SubTask.milestone` |
| `reminder` | `Reminder?` | `.cascade` | — |
| `project` | `Project?` | `.nullify` | `Project.milestones` |

---

### 3.5 SubTask（子任务）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `taskId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `title` | `String` | — | 子任务名称 |
| `isCompleted` | `Bool` | 默认 `false` | 是否完成 |
| `completedAt` | `Date?` | — | 完成时间 |
| `orderIndex` | `Int` | — | 排序索引 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `reminder` | `Reminder?` | `.cascade` | — |
| `milestone` | `Milestone?` | `.nullify` | `Milestone.subtasks` |

---

### 3.6 Memo（备忘录）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `memoId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `content` | `String` | — | 备忘文本内容 |
| `createdAt` | `Date` | — | 创建时间 |
| `orderIndex` | `Int` | 默认 `0` | 排序索引 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `project` | `Project?` | `.nullify` | `Project.memos` |

---

### 3.7 ProjectTemplate（项目模板）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `templateId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `name` | `String` | — | 模板名称 |
| `hideCompleted` | `Bool` | — | 默认隐藏已完成 |
| `orderIndex` | `Int` | — | 排序索引 |
| `accentColor` | `String` | — | 主题色 Hex |
| `sfSymbolName` | `String` | — | SF Symbol 图标名 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `milestones` | `[TemplateMilestone]` | `.cascade` | `TemplateMilestone.template` |

---

### 3.8 TemplateMilestone（模板里程碑）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `milestoneId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `title` | `String` | — | 里程碑名称 |
| `orderIndex` | `Int` | — | 排序索引 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `subtasks` | `[TemplateSubTask]` | `.cascade` | `TemplateSubTask.milestone` |
| `template` | `ProjectTemplate?` | `.nullify` | `ProjectTemplate.milestones` |

---

### 3.9 TemplateSubTask（模板子任务）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `taskId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `title` | `String` | — | 子任务名称 |
| `orderIndex` | `Int` | — | 排序索引 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `milestone` | `TemplateMilestone?` | `.nullify` | `TemplateMilestone.subtasks` |

---

### 3.10 ArchiveFolder（归档文件夹）

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `folderId` | `UUID` | `@Attribute(.unique)` | 唯一标识 |
| `name` | `String` | — | 文件夹名 |
| `orderIndex` | `Int` | — | 排序索引 |

**关系**:

| 关系 | 目标 | deleteRule | inverse |
|------|------|-----------|---------|
| `projects` | `[Project]` | `.nullify` | `Project.archiveFolder` |
| `parent` | `ArchiveFolder?` | `.nullify` | — |
| `children` | `[ArchiveFolder]` | `.cascade` | `ArchiveFolder.parent` |

---

### 3.11 AppSettings（应用设置）

> **双端差异**: AppSettings 是唯一允许双端字段不完全相同的模型。iOS 端只保留跨端通用字段，macOS 专有字段在 iOS 端不创建。SwiftData 对缺失字段具备向前兼容性（存储时忽略未知字段，读取时使用默认值）。

**双端共有字段（必须一致）**:

| 属性 | Swift 类型 | 约束 | 说明 |
|------|-----------|------|------|
| `settingsId` | `String` | `@Attribute(.unique)` | 固定为 `"shared"`，单例 |
| `createdAt` | `Date` | — | 创建时间 |
| `theme` | `String` | — | `"system"` / `"light"` / `"dark"` |
| `language` | `String` | — | `"system"` / `"english"` / `"simplifiedChinese"` |
| `dateFormat` | `String` | — | 日期格式化模板 |
| `syncEnabled` | `Bool` | 默认 `true` | iCloud 同步开关 |
| `lastSyncAt` | `Date?` | — | 上次同步时间 |

**macOS 专有字段（iOS 端不创建）**:

| 属性 | 说明 |
|------|------|
| `launchAtLogin` | 登录自启 |
| `menuBarComponentEnabled` | 菜单栏组件开关 |
| `menuBarIcon` | 菜单栏图标 |
| `menuBarProjectScope` | 菜单栏项目范围 |
| `menuBarContentMode` | 菜单栏内容模式 |
| `overviewScope` | 总览页范围筛选 |
| `weekdayFilterEnabled` | 工作日过滤 |
| `toggleMainPanelShortcut` | 主面板快捷键 |
| `openSearchShortcut` | 搜索快捷键 |
| `backupEnabled` | 备份开关 |
| `backupPath` | 备份路径 |
| `backupBookmarkData` | 安全域书签 |
| `automaticallyChecksForUpdates` | 自动检查更新 |

---

### 3.12 实体-关系总览图

```
Project (1) ──cascade──→ (N) Milestone (1) ──cascade──→ (N) SubTask
    │                         │                              │
    │ cascade                 │ cascade                      │ cascade
    ↓                         ↓                              ↓
  Reminder                Reminder                        Reminder

Project (1) ──cascade──→ (N) Memo
Project (N) ──nullify──→ (1) ArchiveFolder
ArchiveFolder (1) ──cascade──→ (N) ArchiveFolder (children, 自引用树)

ProjectTemplate (1) ──cascade──→ (N) TemplateMilestone (1) ──cascade──→ (N) TemplateSubTask

NotificationScheduleEntry  —— 独立实体，通过 ownerId + ownerKind 关联到 Project/Milestone/SubTask
AppSettings                 —— 单例实体，settingsId = "shared"
```

---

### 3.13 CloudKit 同步兼容性规则

以下规则在修改数据模型时**必须遵守**，否则会导致 CloudKit 同步静默失败或崩溃：

1. **所有属性必须可选或有默认值** — CloudKit 要求每个字段都能安全地表示为 `nil`，因此 `Bool`、`Int` 等值类型必须提供默认值，`String`/`Date` 建议用 Optional
2. **`@Attribute(.unique)` 不可事后添加** — 必须在首次部署 Schema 时就加好；已有数据的字段添加 unique 约束会触发同步冲突
3. **关系必须配置 inverse** — 单向关系在 CloudKit 中行为未定义，必须双向配置
4. **不要使用 enum** — SwiftData 对 RawRepresentable enum 的支持在 CloudKit 场景下不稳定，统一用 `String` + 常量
5. **不要使用 `@Model` 之外的持久化方式** — `@Transient`、手动 `NSManagedObject` 子类化等都会导致 Schema 不一致
6. **新增模型必须同时更新两端的 Schema 数组**（`ViabarApp.swift` / `ViabarIOSApp.swift`）
7. **重命名属性** = 删除旧字段 + 新增字段，旧数据丢失。若需迁移，使用轻量级迁移或在 SwiftData 中用计算属性做兼容层

### 3.14 SwiftData ModelContainer 配置（启用 iCloud）

```swift
// ViabarApp.swift — iOS 端入口
import SwiftUI
import SwiftData

@main
struct ViabarIOSApp: App {
    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            NotificationScheduleEntry.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
            AppSettings.self,
        ])

        // 关键：启用 iCloud CloudKit 同步
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.viabar")
        )

        do {
            sharedModelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
    }
}
```

---

## 4. 核心算法（从 macOS 端继承）

### 4.1 进度 Rollup 计算（Project.progress）

逻辑完全从 macOS `Project.swift:110-124` 继承：

- `N` 个里程碑，每个权重 `1/N`
- 无子任务的里程碑：完成得 `1.0`，未完成得 `0`
- 有 `M` 个子任务的里程碑：`S = 已完成子任务数 / M`
- 项目总进度 `Progress = Σ(S_i / N)`，四舍五入到 4 位小数

### 4.2 上下文穿透（Project.topUnfinishedTitle）

逻辑完全从 macOS `Project.swift:129-144` 继承：

- 查找第一个 `isCompleted == false` 的里程碑
- 若有子任务，精确定位到第一个未完成的子任务
- 用于通知文案和菜单栏显示

### 4.3 通知调度（NotificationScheduleService）

逻辑完全从 macOS `NotificationScheduleService.swift` 继承：

- 单次提醒：指定时间戳触发
- 重复提醒：每天/每N天/每周/每月
- 项目级提醒触发时自动穿透到最顶端未完成任务

---

## 5. iOS 端 UI 架构

### 5.1 导航结构

采用 **TabView + NavigationStack** 的标准 iOS 导航模式：

```
TabView
├── Tab 1: 总览 (OverviewTab)
│     └── NavigationStack
│           ├── OverviewView（项目卡片网格）
│           └── ProjectDetailView（项目详情）
│                 ├── MilestoneListView（里程碑时间线）
│                 └── MemoTimelineView（备忘录，Sheet 形式）
│
├── Tab 2: 搜索 (SearchTab)
│     └── SearchView（全局搜索，内嵌列表）
│
└── Tab 3: 设置 (SettingsTab)
      └── SettingsView
```

### 5.2 关键 UI 适配（macOS → iOS）

| macOS 组件 | iOS 适配方案 |
|------------|-------------|
| 三栏 NavigationSplitView | TabView + NavigationStack，原生 iOS 导航 |
| 侧边栏 (Sidebar) | Tab 1 内嵌 List 或合并到总览页 |
| 右键菜单 (contextMenu) | iOS 原生 `.contextMenu` + 长按手势 |
| 悬浮按钮 (MenuBarExtra) | iOS Widget + 通知中心 |
| 快捷键 (Cmd+F) | `.searchable` modifier + 下拉搜索栏 |
| 拖拽排序 (onDrag/onDrop) | `.onMove` + EditButton |
| 抽屉面板 (MemoDrawer) | Sheet 或 NavigationLink 进入独立页面 |
| 悬浮工具栏按钮 | NavigationBar trailing items |
| 窗口尺寸控制 (frame/minWidth) | 自适应 SafeArea |

### 5.3 设计系统（从 ViabarColor 继承）

```swift
// 完全复用 macOS 端 ViabarColor.swift 的色板
// 主色调
static let primary      = Color(hex: "#0085ff")   // 深蓝
static let primaryLight = Color(hex: "#00BFFF")   // 浅蓝
static let primaryPale  = Color(hex: "#e0ffff")   // 极浅蓝

// 状态色
static let danger  = Color(hex: "#FF4B41")   // 红
static let warning = Color(hex: "#FFBF00")   // 黄
static let success = Color(hex: "#09CC9B")   // 绿
static let info    = Color(hex: "#2BB7FD")   // 蓝

// 项目可选主题色（Palette），macOS 端定义的 10 种颜色完全复用
```

### 5.4 项目卡片设计（OverviewProjectCard iOS 版）

将 macOS 端 `ContentView.swift` 中的 `OverviewProjectCard` 适配为 iOS 风格：

- 去除 NSWindow 相关的背景色自适应代码
- 使用 `@Environment(\.colorScheme)` 替代 `NSAppearance`
- 保留：顶部彩色 Header（项目图标 + 名称）、首个里程碑、提醒时间、进度点 + 百分比
- 交互：点击卡片 → Push 进入 `ProjectDetailView`
- 长按卡片 → ContextMenu（编辑/收藏/归档/删除）

---

## 6. 组件复用清单

以下文件可以从 macOS 端**直接复制**到 iOS 端，无需或仅需微小修改：

| 文件 | 复用方式 | 修改点 |
|------|---------|--------|
| `Models/Project.swift` | 直接复制 | 无 |
| `Models/GlobalSearch.swift` | 直接复制 | 无 |
| `Models/OverviewReport.swift` | 直接复制 | 无 |
| `Models/ReminderDisplay.swift` | 直接复制 | 无 |
| `Models/MenuBarContent.swift` | 直接复制（重命名为 `TaskContent.swift`） | 去除 MenuBar 命名 |
| `Models/AppSettings.swift` | 部分复制，裁剪 macOS 专有字段 | 见 3.2 节 |
| `Models/BackupSnapshot.swift` | 直接复制 | iOS 端备份功能可选 |
| `System/ViabarColor.swift` | 直接复制 | 去除 NSColor/AppKit 引用，纯 SwiftUI Color |
| `Services/ProjectService.swift` | 直接复制 | 去除 BackupService 依赖 |
| `Services/NotificationScheduleService.swift` | 直接复制 | 无 |
| `Services/SyncService.swift` | 直接复制 | 无 |
| `Views/Component/Color+Hex.swift` | 直接复制 | 无 |
| `Views/Component/ProgressBarView.swift` | 直接复制 | 无 |
| `Views/Component/SearchTargetHighlight.swift` | 直接复制 | 无 |
| `Views/Component/ReminderSettingsPopover.swift` | 修改为 Sheet | Popover → Sheet |

---

## 7. iOS 端专属新文件

### 7.1 ViabarIOSApp.swift（App 入口）

```swift
@main
struct ViabarIOSApp: App {
    // 使用 CloudKit 配置的 ModelContainer
    // 注册 ServiceContainer、ProjectService、NotificationScheduleService
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serviceContainer)
                .modelContainer(sharedModelContainer)
        }
    }
}
```

### 7.2 ContentView.swift（根视图，TabView）

```swift
struct ContentView: View {
    @State private var selectedTab: AppTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewTabView()
                .tabItem { Label("总览", systemImage: "square.grid.2x2") }
                .tag(AppTab.overview)

            SearchTabView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            SettingsTabView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
```

### 7.3 Views/Overview/OverviewView.swift

- 沿用 macOS 端 `OverviewDashboardView` 的 LazyVGrid 布局
- 每个卡片点击 Push 到 `ProjectDetailView`
- 导航栏 trailing 按钮：`+` 新建项目

### 7.4 Views/ProjectDetail/ProjectDetailView.swift

- 顶部项目名称 + 进度条
- 分段控件 (Picker segmented)：`里程碑` | `备忘录`
- 里程碑列表：垂直时间线，每个单元格左侧圆点连线
- 备忘录列表：时间轴列表 + 底部固定输入框

### 7.5 Views/ProjectDetail/MilestoneListView.swift（iOS 版）

- 从 macOS 端 `MilestoneListView.swift` 适配
- 使用 iOS 原生 List + swipe actions
- 里程碑行：checkbox + 标题 + SF Symbol 提醒图标
- 子任务行：缩进 + checkbox + 标题
- 左滑操作：删除
- `.searchable` 支持本地筛选

### 7.6 Views/ProjectDetail/MemoTimelineView.swift（iOS 版）

- 从 macOS 端适配
- 备忘录列表 + 底部 TextField + 发送按钮
- 每条备忘录显示时间戳

### 7.7 Views/Search/SearchView.swift

- 使用 `.searchable` modifier
- 搜索结果列表，按项目分组
- 点击结果 → Push 到对应项目详情页并高亮目标

### 7.8 Views/Settings/SettingsView.swift（iOS 版）

```
SettingsView (Form)
├── Section: 外观
│     ├── 主题选择 (system/light/dark)
│     └── 语言选择 (system/English/简体中文)
├── Section: 同步
│     ├── iCloud 同步开关
│     └── 上次同步时间
├── Section: 数据
│     └── 日期格式选择
└── Section: 关于
      ├── 版本号
      └── 隐私政策链接
```

### 7.9 Widget/ViabarWidget.swift

- WidgetKit 中等尺寸组件
- 展示最多 3 个星标项目的进度条 + 名称
- 点击跳转 App 对应项目

---

## 8. 目录结构

```
Viabar-iOS/
├── CLAUDE.md                          # 本文档
├── ViabarIOSApp.swift                 # App 启动入口，CloudKit ModelContainer
├── ContentView.swift                  # TabView 根视图
├── Assets.xcassets                    # 图标与资产
│
├── 📂 Models/                         # 从 macOS 端同步（直接复制）
│   ├── Project.swift
│   ├── GlobalSearch.swift
│   ├── OverviewReport.swift
│   ├── ReminderDisplay.swift
│   ├── TaskContent.swift              # 从 MenuBarContent.swift 重命名
│   ├── AppSettings.swift              # 裁剪 macOS 专有字段
│   └── BackupSnapshot.swift           # 可选
│
├── 📂 Services/                       # 从 macOS 端同步（直接复制）
│   ├── ProjectService.swift
│   ├── NotificationScheduleService.swift
│   └── SyncService.swift
│
├── 📂 System/                         # 系统配置
│   └── ViabarColor.swift              # 从 macOS 端复制，去除 AppKit
│
├── 📂 Views/
│   ├── Overview/
│   │   ├── OverviewView.swift         # 项目卡片网格总览
│   │   └── OverviewProjectCard.swift  # iOS 版项目卡片
│   ├── ProjectDetail/
│   │   ├── ProjectDetailView.swift    # 项目详情（分段控件）
│   │   ├── MilestoneListView.swift    # iOS 版里程碑时间线
│   │   └── MemoTimelineView.swift     # iOS 版备忘录列表
│   ├── Search/
│   │   └── SearchView.swift           # 全局搜索页
│   ├── Settings/
│   │   └── SettingsView.swift         # iOS 版设置页
│   └── Component/                     # 从 macOS 端复制
│       ├── Color+Hex.swift
│       ├── ProgressBarView.swift
│       ├── SearchTargetHighlight.swift
│       └── ReminderSettingsView.swift # iOS 版提醒设置（Sheet）
│
└── 📂 Widget/
    └── ViabarWidget.swift             # WidgetKit 桌面组件
```

---

## 9. 开发路线图 (iOS MVP)

### Phase 1: 数据层搭建（第 1-2 天）

- [ ] 创建 Xcode iOS 项目，配置 CloudKit Container `iCloud.com.viabar`
- [ ] 从 macOS 端复制全部 Model 文件
- [ ] 配置 SwiftData `ModelContainer`（cloudKitDatabase 模式）
- [ ] 验证 iCloud 同步：在 macOS 端创建项目，iOS 端确认可见
- [ ] 裁剪 AppSettings，去除 macOS 专有字段

### Phase 2: 服务层集成（第 3-4 天）

- [ ] 从 macOS 端复制 `ProjectService.swift`
- [ ] 从 macOS 端复制 `NotificationScheduleService.swift`
- [ ] 从 macOS 端复制 `SyncService.swift`
- [ ] 实现 `ServiceContainer` 注册与 Environment 注入
- [ ] 验证 CRUD 操作 + iCloud 双向同步

### Phase 3: 总览页与项目详情页（第 5-8 天）

- [ ] 实现 `OverviewView` + `OverviewProjectCard`（iOS 适配版）
- [ ] 实现 `ProjectDetailView`（分段控件：里程碑 | 备忘录）
- [ ] 实现 `MilestoneListView`（垂直时间线 + Swipe Actions）
- [ ] 实现 `MemoTimelineView`（备忘录列表 + 底部输入框）
- [ ] 新建项目 Sheet（复用 macOS 端 `NewProjectView` 逻辑）
- [ ] 提醒设置 Sheet（复用 macOS 端 `ReminderSettingsPopover` 逻辑）

### Phase 4: 搜索与设置（第 9-10 天）

- [ ] 实现 `SearchView`（全局搜索 + 结果跳转 + 高亮闪烁动画）
- [ ] 实现 `SettingsView`（外观/语言/同步/关于）
- [ ] 实现 AppAppearanceController（主题切换）
- [ ] 实现 AppLanguageController（中/英切换）

### Phase 5: Widget 与收尾（第 11-12 天）

- [ ] 实现 WidgetKit 中等尺寸组件
- [ ] 本地通知权限请求与调度
- [ ] UI 细节打磨（动画、间距、颜色一致性）
- [ ] 深色模式适配测试
- [ ] 中英文国际化覆盖
- [ ] TestFlight 内部测试

---

## 10. macOS 端需要做的兼容性调整

为配合 iOS 端实现零摩擦 iCloud 同步，macOS 端需要进行以下调整：

1. **启用 CloudKit** — 将 `ViabarApp.swift` 中注释掉的 `cloudKitDatabase: .private("iCloud.com.viabar")` 配置正式激活
2. **AppSettings 兼容** — 新增字段时确保 iOS 端裁剪版本不会因缺失字段而崩溃（SwiftData 会自动处理可选字段）
3. **CloudKit Dashboard 配置** — 在 CloudKit Console 中为 `iCloud.com.viabar` Container 添加 Schema 部署

---

## 11. 关键设计决策记录

| 决策 | 选择 | 原因 |
|------|------|------|
| iOS 导航模式 | TabView | 标准 iOS 模式，用户无需学习 |
| 备忘录展示 | 分段控件内嵌 | 避免过度导航，保持项目上下文 |
| 侧边栏 | 合并到总览 Tab | 减少导航层级，Tab 数量控制在 3 个 |
| 归档功能 | Phase 2 | MVP 先聚焦活跃项目 |
| 备份功能 | 不纳入 iOS MVP | iCloud 已提供数据冗余；备份为 macOS 端专属 |
| 模板功能 | Phase 2 | 新建项目时可从模板创建 |
| Widget | 仅中号组件 | 在锁屏/桌面有效展示进度，小号信息密度不足 |
| 零第三方依赖 | 坚持 | 与 macOS 端策略一致，降低维护成本 |
