# 今日推进功能实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在总览页顶部增加响应式“今日推进”区域，并增加一个使用同一推荐引擎的大号“今日推进”Widget。

**Architecture:** 使用非持久化 `TodayFocusItem`、候选提供协议和统一 `TodayFocusEngine` 计算最多三个推荐项。主 App 与 Widget 只负责本地化和展示，复用现有任务完成、深链导航与搜索高亮链路。

**Tech Stack:** Swift 5.10+、SwiftUI、SwiftData、WidgetKit、AppIntents、Apple 原生框架。

## Global Constraints

- 使用中文交流。
- 不编译代码，不运行测试；只执行静态检查。
- 不提交代码。
- 不修改任何 `@Model`、SwiftData schema、数据库路径、备份格式或 CloudKit 配置。
- 不处理当前 ad-hoc 签名造成的 Widget App Group 可用性问题。
- 任务树保持 `Project -> Milestone -> SubTask`，不增加第三层。
- 所有新增用户可见文案同步更新英文和简体中文资源。
- UI 必须同时支持深色和浅色模式。
- 保留现有可选择项目的中号和大号 Widget。

---

## 文件结构

- 新建 `Viabar/Models/TodayFocus.swift`：共享推荐模型、候选协议、规则候选源、统一过滤与排序引擎、下一刷新边界计算。
- 新建 `Viabar/Views/Component/TodayFocusSectionView.swift`：总览区域、响应式布局、推荐卡片和空状态。
- 修改 `Viabar/ContentView.swift`：计算推荐、接入区域、完成任务、构造精确高亮请求。
- 新建 `ViabarWidget/ViabarTodayFocusWidget.swift`：大号 Widget provider、entry、视图和交互。
- 修改 `ViabarWidget/ViabarWidgetBundle.swift`：注册新增 Widget。
- 修改 `ViabarWidget/ViabarLargeWidget.swift`：将深链 URL 构造器从文件私有提升为 Widget 共享符号。
- 修改 `ViabarWidget/ToggleWidgetTaskIntent.swift`：刷新包含今日推进在内的全部 Widget kind。
- 修改 `Viabar/System/SharedModelContainer.swift`：增加今日推进 Widget kind。
- 修改 `Viabar.xcodeproj/project.pbxproj`：把 `TodayFocus.swift` 加入 macOS/iOS Widget Extension Sources。
- 修改 `Viabar/en.lproj/Localizable.strings` 与 `Viabar/zh-Hans.lproj/Localizable.strings`：增加完整中英文文案。

---

### Task 1：共享推荐模型与规则引擎

**Files:**
- Create: `Viabar/Models/TodayFocus.swift`
- Modify: `Viabar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `[Project]`、`Reminder.displayFireDate`、`Milestone.completedAt`、`SubTask.completedAt`、`WidgetTaskKind`。
- Produces: `TodayFocusItem`、`TodayFocusReason`、`TodayFocusCandidateProvider`、`RuleBasedTodayFocusProvider`、`TodayFocusEngine.items(projects:now:calendar:limit:)`、`TodayFocusEngine.nextRefreshDate(items:now:calendar:)`。

- [ ] **Step 1：定义非持久化共享类型**

在 `Viabar/Models/TodayFocus.swift` 定义固定接口：

```swift
import Foundation

enum TodayFocusSource: Equatable {
    case rule
    case ai
}

enum TodayFocusReason: Equatable {
    case overdue
    case today
    case favorite
    case stalled(days: Int)
    case projectOrder
    case aiSuggested
}

struct TodayFocusItem: Identifiable, Equatable {
    let projectID: UUID
    let projectTitle: String
    let projectSymbolName: String
    let projectAccentColor: String
    let projectProgress: Double
    let projectOrderIndex: Int
    let taskID: UUID
    let taskKind: WidgetTaskKind
    let milestoneID: UUID
    let taskTitle: String
    let reminderDate: Date?
    let source: TodayFocusSource
    let reason: TodayFocusReason
    let latestCompletionDate: Date?

    var id: UUID { taskID }
}

protocol TodayFocusCandidateProvider {
    func candidates(projects: [Project], now: Date, calendar: Calendar) -> [TodayFocusItem]
}
```

- [ ] **Step 2：实现每项目一个候选的上下文穿透**

`RuleBasedTodayFocusProvider` 必须：

```swift
struct RuleBasedTodayFocusProvider: TodayFocusCandidateProvider {
    func candidates(projects: [Project], now: Date, calendar: Calendar) -> [TodayFocusItem] {
        projects
            .filter { !$0.isArchived }
            .compactMap { candidate(for: $0, now: now, calendar: calendar) }
    }
}
```

`candidate(for:)` 按 `orderIndex` 选择第一个未完成里程碑；若存在未完成子任务则选择第一个未完成子任务，否则选择里程碑。提醒取最终被推荐任务自身的 `reminder?.displayFireDate`，不得回退到项目提醒或父里程碑提醒。

- [ ] **Step 3：实现停滞时间与原因分级**

最新完成时间取项目所有里程碑与子任务非空 `completedAt` 的最大值：

```swift
let latestCompletion = (
    project.milestones.compactMap(\.completedAt)
    + project.milestones.flatMap { $0.subtasks.compactMap(\.completedAt) }
).max()
```

原因必须严格按以下顺序判定：

```swift
if let reminderDate, reminderDate < now { return .overdue }
if let reminderDate, calendar.isDate(reminderDate, inSameDayAs: now) { return .today }
if project.isFavorite { return .favorite }
if let latestCompletion,
   let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: latestCompletion), to: calendar.startOfDay(for: now)).day,
   days >= 7 { return .stalled(days: days) }
return .projectOrder
```

从未有完成记录的项目不得判定为停滞。

- [ ] **Step 4：实现统一校验、去重、排序和截断**

`TodayFocusEngine` 构造时注入候选源，默认使用规则源：

```swift
struct TodayFocusEngine {
    let providers: [any TodayFocusCandidateProvider]

    init(providers: [any TodayFocusCandidateProvider] = [RuleBasedTodayFocusProvider()]) {
        self.providers = providers
    }

    func items(
        projects: [Project],
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [TodayFocusItem]
}
```

最终处理顺序：合并候选、按当前 `Project`/任务状态验证、每个项目保留排序最优的一项、稳定排序、返回 `prefix(max(0, limit))`。排序等级为 overdue、today、favorite、stalled、projectOrder、aiSuggested；提醒类按时间升序，停滞按天数降序，之后按 `projectOrderIndex` 与 `projectTitle.localizedStandardCompare`。

- [ ] **Step 5：实现下一 Timeline 边界**

`nextRefreshDate` 返回以下未来时间的最小值，并以 `now + 15 分钟` 作为上限：

- 下一次午夜。
- 推荐项中晚于 `now` 的最近提醒时间。
- 有最新完成记录但尚未停滞的项目，其 `startOfDay(latestCompletion) + 7 天` 边界。

返回值必须严格晚于 `now`，避免 Widget 产生立即循环刷新。

- [ ] **Step 6：配置共享 target membership**

在 `Viabar.xcodeproj/project.pbxproj` 中为 `Viabar/Models/TodayFocus.swift` 增加文件引用，并加入 macOS `ViabarWidgetExtension` 和 iOS `ViabariOSWidgetExtension` 的 Sources。主 App 的 `Viabar` 同步目录自动包含该文件，不重复添加。

- [ ] **Step 7：静态核对引擎约束**

运行：

```bash
rg -n "@Model|TodayFocusReason|TodayFocusCandidateProvider|RuleBasedTodayFocusProvider|limit: Int = 3|days >= 7" Viabar/Models/TodayFocus.swift
rg -n "TodayFocus.swift in Sources" Viabar.xcodeproj/project.pbxproj
```

预期：`TodayFocus.swift` 不包含 `@Model`；两个 Widget Extension Sources 均包含共享文件。

---

### Task 2：总览今日推进区域与精确导航

**Files:**
- Create: `Viabar/Views/Component/TodayFocusSectionView.swift`
- Modify: `Viabar/ContentView.swift`

**Interfaces:**
- Consumes: `[TodayFocusItem]`、`AppSettings.dateFormat`、`TaskCompletionMutation`、`GlobalSearchNavigationRequest`。
- Produces: `TodayFocusSectionView(items:availableWidth:dateFormatPattern:onOpen:onToggle:)`。

- [ ] **Step 1：创建区域 View 接口**

```swift
struct TodayFocusSectionView: View {
    let items: [TodayFocusItem]
    let availableWidth: CGFloat
    let dateFormatPattern: String?
    let onOpen: (TodayFocusItem) -> Void
    let onToggle: (TodayFocusItem) -> Void
}
```

区域固定显示本地化标题“今日推进”和数量；候选为空时显示本地化空状态。

- [ ] **Step 2：实现确定性的响应式布局**

设置单一断点 `760` 点：

```swift
private var usesStackedLayout: Bool { availableWidth < 760 }
```

- 宽布局：主推荐使用 `layoutPriority(1)` 和约两倍次推荐的宽度，三个卡片单行。
- 窄布局：主推荐独占第一行；第二、第三推荐在第二行等宽排列。
- 两个推荐时，第二行保留一个空等宽槽，第二项不拉伸。
- 一个推荐时只渲染主推荐行。
- 禁止使用横向 `ScrollView`。

- [ ] **Step 3：实现支持深浅色的卡片**

卡片使用 `Color(nsColor: .controlBackgroundColor)`、`.primary`、`.secondary` 和动态描边；项目主题色仅用于图标与小面积状态条。完成按钮与正文点击区域分离，避免完成操作同时触发导航。

卡片至少显示：任务标题、项目名称、原因、可选提醒时间和项目进度。日期使用 `AppDateFormatter.string(from:pattern:)`。

- [ ] **Step 4：在总览顶部接入共享推荐结果**

在 `OverviewDashboardView` 中增加：

```swift
@Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]

private var todayFocusItems: [TodayFocusItem] {
    TodayFocusEngine().items(projects: visibleProjects)
}
```

在收藏项目 section 前插入 `TodayFocusSectionView`。传入实际可用宽度：

```swift
let availableWidth = max(1, proxy.size.width - trailingPanelWidth - contentPadding * 2)
```

- [ ] **Step 5：补充完成回调**

根据 `taskKind` 和 ID 在当前 `projects` 中重新解析实体；仍未完成时调用：

```swift
switch item.taskKind {
case .milestone:
    projectService?.toggleMilestoneComplete(milestone)
case .subTask:
    projectService?.toggleSubTaskComplete(subtask)
}
```

若实体已删除、已完成或项目已归档，直接返回，不恢复旧状态。

- [ ] **Step 6：补充精确高亮导航**

将 `OverviewDashboardView.onSelectProject` 扩展或新增 `onOpenTodayFocusItem` 回调，由 `ContentView` 构造：

```swift
let destination: GlobalSearchDestination = switch item.taskKind {
case .milestone:
    .milestone(item.milestoneID)
case .subTask:
    .subTask(milestoneID: item.milestoneID, subTaskID: item.taskID)
}
navigationRequest = GlobalSearchNavigationRequest(projectID: item.projectID, destination: destination)
selection = .project(project)
```

- [ ] **Step 7：静态检查总览接入**

```bash
rg -n "TodayFocusSectionView|TodayFocusEngine|onOpenTodayFocusItem|TaskCompletionMutation" Viabar/ContentView.swift Viabar/Views/Component/TodayFocusSectionView.swift
```

预期：总览只调用共享引擎，不包含第二套优先级排序。

---

### Task 3：今日推进大型 Widget

**Files:**
- Create: `ViabarWidget/ViabarTodayFocusWidget.swift`
- Modify: `ViabarWidget/ViabarWidgetBundle.swift`
- Modify: `ViabarWidget/ViabarLargeWidget.swift`
- Modify: `Viabar/System/SharedModelContainer.swift`
- Modify: `ViabarWidget/ToggleWidgetTaskIntent.swift`

**Interfaces:**
- Consumes: `TodayFocusEngine`、`TodayFocusItem`、`ToggleWidgetTaskIntent`、`ViabarWidgetNavigationURL`、共享 SwiftData 容器。
- Produces: `ViabarTodayFocusWidget`、`ViabarTodayFocusProvider`、`ViabarTodayFocusEntry`。

- [ ] **Step 1：注册新的 Widget kind**

在 `SharedModelContainer` 增加：

```swift
static let todayFocusWidgetKind = "ViabarTodayFocusWidget"
static let widgetKinds = [mediumWidgetKind, largeWidgetKind, todayFocusWidgetKind]
```

`ToggleWidgetTaskIntent` 继续遍历 `widgetKinds`，无需建立新的完成 Intent。

- [ ] **Step 2：共享现有深链 URL 构造器**

将 `ViabarLargeWidget.swift` 中的 `private enum ViabarWidgetNavigationURL` 改为模块内可见 `enum ViabarWidgetNavigationURL`，保持 `project`、`milestone`、`subTask` 签名不变。

- [ ] **Step 3：实现 Widget entry 与 provider**

```swift
enum ViabarTodayFocusState {
    case unavailable
    case empty
    case content([TodayFocusItem])
}

struct ViabarTodayFocusEntry: TimelineEntry {
    let date: Date
    let state: ViabarTodayFocusState
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage
}

struct ViabarTodayFocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ViabarTodayFocusEntry
    func getSnapshot(in context: Context, completion: @escaping (ViabarTodayFocusEntry) -> Void)
    func getTimeline(in context: Context, completion: @escaping (Timeline<ViabarTodayFocusEntry>) -> Void)
}
```

Provider 在 `@MainActor` 辅助方法中打开共享容器，读取 `Project` 和首条 `AppSettings`，解析 `EffectiveAppLanguage`，调用 `TodayFocusEngine().items(projects:)`，并使用 `nextRefreshDate` 设置 `.after(date)`。读取失败返回 `.unavailable`，无推荐返回 `.empty`。Widget 根视图注入 `.environment(\.locale, entry.language.locale)`，使应用内语言设置对 Widget 文案生效。

- [ ] **Step 4：实现大号 Widget 配置和内容**

```swift
struct ViabarTodayFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedModelContainer.todayFocusWidgetKind,
            provider: ViabarTodayFocusProvider()
        ) { entry in
            ViabarTodayFocusWidgetView(entry: entry)
        }
        .configurationDisplayName("今日推进")
        .description("展示当前最值得推进的任务")
        .supportedFamilies([.systemLarge])
    }
}
```

视图最多渲染三行，每行正文用 `Link` 指向精确任务 URL，右侧使用：

```swift
Button(intent: ToggleWidgetTaskIntent(kind: item.taskKind, taskID: item.taskID)) {
    Image(systemName: "circle")
}
.buttonStyle(.plain)
```

使用 `.containerBackground(.background, for: .widget)`、`.primary`、`.secondary` 和动态状态色适配深浅色。

- [ ] **Step 5：注册 Widget**

在 `ViabarWidgetBundle` 追加：

```swift
ViabarTodayFocusWidget()
```

保留 `ViabarMediumWidget()` 和 `ViabarLargeWidget()`。

- [ ] **Step 6：静态检查 Widget 接入**

```bash
rg -n "ViabarTodayFocusWidget|systemLarge|StaticConfiguration|TodayFocusEngine|ToggleWidgetTaskIntent|widgetKinds" ViabarWidget Viabar/System/SharedModelContainer.swift
```

预期：新增 Widget 无项目选择参数，三个 Widget 均保留，完成操作刷新三个 kind。

---

### Task 4：国际化与文案映射

**Files:**
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`
- Modify: `ViabarWidget/ViabarTodayFocusWidget.swift`

**Interfaces:**
- Consumes: `TodayFocusReason`、当前 SwiftUI locale、`AppDateFormatter`。
- Produces: 主 App 和 Widget 一致的推荐原因文案。

- [ ] **Step 1：增加成对本地化条目**

至少增加以下键，并确保两份文件键集合一致：

```text
今日推进
%d 项
今天没有需要推进的任务
暂时无法读取今日推进
提醒已逾期
今天需要处理
收藏项目
已 %d 天未推进
按项目顺序推荐
AI 建议
展示当前最值得推进的任务
```

英文值分别使用 `Today Focus`、`%d items`、`Nothing needs your attention today`、`Today Focus is temporarily unavailable`、`Overdue`、`Due today`、`Favorite project`、`No progress for %d days`、`Project order`、`AI suggestion`、`Shows the tasks most worth moving forward now`。

- [ ] **Step 2：建立 View 层原因映射**

主 App 和 Widget 不直接 switch 出硬编码语言。增加模块内共享函数或 `TodayFocusReason` 的 View 辅助扩展，根据枚举返回 `LocalizedStringKey`；带天数的停滞原因使用本地化格式化。算法文件不得依赖 SwiftUI 或用户语言。

- [ ] **Step 3：检查深浅色和文案硬编码**

```bash
rg -n "Color\.(white|black)|\.foregroundColor\(\.white\)|Today Focus|Overdue|Due today" Viabar/Views/Component/TodayFocusSectionView.swift ViabarWidget/ViabarTodayFocusWidget.swift
```

预期：没有固定黑白前景色；英文文案只出现在本地化资源中。

---

### Task 5：最终静态验证与范围审计

**Files:**
- Verify all files changed by Tasks 1-4.

**Interfaces:**
- Consumes: 完整未提交差异。
- Produces: 静态验证结果和未验证事项说明。

- [ ] **Step 1：检查数据库结构未变化**

```bash
git diff -- Viabar/Models/Project.swift Viabar/System/SharedModelContainer.swift Viabar/Models/BackupSnapshot.swift Viabar/Services/BackupService.swift
rg -n "@Model|Schema\(" Viabar/Models/TodayFocus.swift
```

预期：`Project.swift`、备份模型与服务无修改；`SharedModelContainer.schema` 实体列表无变化；`TodayFocus.swift` 无 `@Model`。

- [ ] **Step 2：检查推荐引擎单一来源**

```bash
rg -n "TodayFocusEngine\(\)\.items|RuleBasedTodayFocusProvider|case overdue|case stalled" Viabar ViabarWidget --glob '*.swift'
```

预期：规则排序只存在于 `TodayFocus.swift`；总览和 Widget 都调用同一引擎。

- [ ] **Step 3：检查本地化文件**

```bash
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

预期：两份文件均输出 `OK`。

- [ ] **Step 4：检查工程文件**

```bash
plutil -lint Viabar.xcodeproj/project.pbxproj
rg -n "TodayFocus.swift in Sources" Viabar.xcodeproj/project.pbxproj
```

预期：工程文件输出 `OK`；macOS/iOS Widget Extension 均包含共享推荐文件。

- [ ] **Step 5：检查差异格式和用户改动**

```bash
git diff --check
git status --short
```

预期：`git diff --check` 无输出；`default.profraw` 保持用户原有修改状态且未出现在本功能 diff 中。

- [ ] **Step 6：交付说明**

最终明确报告：已完成哪些入口、静态检查结果、未修改 schema、未处理 Widget 签名、未编译、未运行测试、未提交。

---

### Task 6：iOS 主 App 今日推进区域

**Files:**
- Create: `ViabariOS/Persistence/IOSTodayFocusSectionView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `ViabariOS/en.lproj/Localizable.strings`
- Modify: `ViabariOS/zh-Hans.lproj/Localizable.strings`
- Modify: `Viabar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TodayFocusEngine`、`TodayFocusItem`、`IOSPersistenceCoordinator.navigate(to:)`、`ProjectService`。
- Produces: `IOSTodayFocusSectionView(items:dateFormatPattern:language:onOpen:onToggle:)`。

- [ ] **Step 1：将共享引擎加入 iOS App target**

在 `Viabar.xcodeproj/project.pbxproj` 为现有 `TodayFocus.swift` 文件引用新增一个 iOS App Sources build file，并加入 `C3AE2DED2FCE63B900528C34` Sources。不得新建或复制推荐引擎文件。

- [ ] **Step 2：创建 iOS 单列区域**

新增：

```swift
struct IOSTodayFocusSectionView: View {
    let items: [TodayFocusItem]
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage
    let onOpen: (TodayFocusItem) -> Void
    let onToggle: (TodayFocusItem) -> Void
}
```

使用 `VStack` 顺序渲染最多三项。每项整行等宽；第一项使用较大标题、间距和状态强调，后两项使用紧凑密度。卡片显示项目、任务、推荐原因、可选提醒时间与进度，并使用 iOS 语义色适配深浅色。

- [ ] **Step 3：接入 iOS 总览顶部**

在 `IOSPersistentOverviewView.overview` 顶部操作按钮之后、星标项目之前插入区域。候选必须直接来自：

```swift
private var todayFocusItems: [TodayFocusItem] {
    TodayFocusEngine().items(projects: projects)
}
```

- [ ] **Step 4：实现精确跳转与完成操作**

正文点击根据 `taskKind` 构造 `GlobalSearchNavigationRequest`，调用 `coordinator.navigate(to:)`。完成操作先从当前 `projects` 重新解析未归档项目、未完成里程碑或子任务，再调用 `services.projectService` 的现有完成方法。

- [ ] **Step 5：补齐 iOS 本地化**

将主 App 已有的今日推进键同步加入 `ViabariOS/en.lproj/Localizable.strings` 和 `ViabariOS/zh-Hans.lproj/Localizable.strings`，至少包含标题、数量、空状态、完成提示和全部推荐原因。

- [ ] **Step 6：执行静态验证**

```bash
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
plutil -lint ViabariOS/en.lproj/Localizable.strings ViabariOS/zh-Hans.lproj/Localizable.strings
xcrun swift-format lint ViabariOS/Persistence/IOSTodayFocusSectionView.swift
rg -n "TodayFocus.swift in Sources" Viabar.xcodeproj/project.pbxproj
```

预期：iOS App、macOS Widget 与 iOS Widget Sources 都引用同一个 `TodayFocus.swift`；新增 iOS Swift 文件无解析错误；不运行编译或测试。

---

### Task 7：macOS 今日推进布局与视觉修订

**Files:**
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`

**Interfaces:**
- Consumes: `TodayFocusItem`、`LightGlassView`、`ViabarColor`、`AppDateFormatter`、现有 `onOpen` 与 `onToggle` 回调。
- Produces: 严格 `50% / 25% / 25%` 的宽屏布局，以及与 `OverviewProjectCard` 一致的 macOS 卡片视觉层级。

- [x] **Step 1：将宽屏卡片改为明确宽度**

在 `horizontalCards` 内先扣除两段间距，再计算三列宽度：

```swift
let usableWidth = max(0, availableWidth - cardSpacing * 2)
let primaryWidth = usableWidth * 0.5
let secondaryWidth = usableWidth * 0.25
```

主推荐使用 `.frame(width: primaryWidth)`，两个次推荐分别使用 `.frame(width: secondaryWidth)`；删除主卡 `.frame(maxWidth: .infinity)`、`.layoutPriority(2)` 和次卡 `availableWidth * 0.24` 的近似计算。少于三项时不重新分配剩余槽位：一项保持主卡宽度，两项保持 `50% + 25%`。

- [x] **Step 2：让区域标题匹配项目区域标题**

将标题样式对齐 `OverviewDashboardView.sectionHeader(icon:title:)`：

```swift
HStack(spacing: 6) {
    Image(systemName: "scope")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    Text(AppLocalization.string("今日推进", language: language))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    Spacer()
    // 保留右侧数量
}
.padding(.top, 8)
```

不得继续使用 `ViabarColor.primary` 强调标题图标。

- [x] **Step 3：重排卡片信息层级与完成按钮**

将卡片正文从“左侧独立完成按钮 + 右侧全部内容”改为单个纵向信息结构：

```swift
VStack(alignment: .leading, spacing: isPrimary ? 12 : 10) {
    projectHeader

    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Button(action: onToggle) {
            Image(systemName: "circle")
        }
        .buttonStyle(.plain)
        .help(Text(AppLocalization.string("标记为完成", language: language)))

        Text(item.taskTitle)
    }

    reasonAndReminder
    ProgressView(value: item.projectProgress)
}
```

`projectHeader` 只显示项目图标、项目名称和右侧进度百分比。完成圆圈必须紧贴任务或子任务标题，不能位于整个项目卡片左上角。任务正文点击仍调用 `onOpen`，完成按钮只能调用 `onToggle`，不得同时触发导航。

- [x] **Step 4：移除推荐原因彩色状态点**

删除 `reasonAndReminder` 中的 `Circle().fill(reasonColor)`。根据原因显示小尺寸语义图标：

```swift
private var reasonSymbolName: String {
    switch item.reason {
    case .overdue, .today: "alarm.fill"
    case .favorite: "star.fill"
    case .stalled: "clock.arrow.circlepath"
    case .projectOrder: "list.number"
    case .aiSuggested: "sparkles"
    }
}
```

原因图标与文字可使用 `reasonColor`，但不得再出现脱离文字的红色或黄色状态圆点。

- [x] **Step 5：应用项目卡片的玻璃 Surface**

卡片外层使用与 `OverviewProjectCard` 相同的视觉参数：

- 24 点连续圆角。
- `LightGlassView` 玻璃层。
- 深色模式白色低透明覆盖层。
- 深色模式白色渐变描边、浅色模式黑色渐变描边。
- 静止阴影半径 6、纵向偏移 2.5；悬停阴影半径 15、纵向偏移 7。
- 悬停时整体上移 2 点，动画时长 0.16 秒。

保留主推荐与次推荐的字号和密度差异，但三张卡片使用同一套 Surface。不得修改 `OverviewProjectCard`，避免扩大回归范围。

- [x] **Step 6：静态核对布局、交互和范围**

运行：

```bash
rg -n "primaryWidth|secondaryWidth|availableWidth \\* 0\\.24|layoutPriority|reasonSymbolName|LightGlassView|Circle\\(\\)" Viabar/Views/Component/TodayFocusSectionView.swift
git diff --check -- Viabar/Views/Component/TodayFocusSectionView.swift
git diff -- Viabar/Views/Component/TodayFocusSectionView.swift Viabar/ContentView.swift ViabariOS ViabarWidget
```

预期：宽屏宽度只使用明确的 `50% / 25% / 25%` 计算；完成圆圈只存在于任务标题行；推荐原因行不包含状态圆点；`ContentView.swift`、iOS 和 Widget 没有因本次视觉修订产生新差异。不编译、不运行测试、不提交。

---

### Task 8：macOS 卡片交互、进度环与七语种本地化

**Files:**
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`
- Modify: `Viabar/Models/AppSettings.swift`
- Modify: `Viabar/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings`
- Create: `ViabarWidget/{ja,ko,de,fr,es}.lproj/Localizable.strings`
- Modify: `ViabarWidget/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `TodayFocusItem.projectProgress`、`onOpen`、`onToggle`、`AppLanguage.title`、`AppLocalization`。
- Produces: 三张固定高 `187` 的 macOS 推荐卡、项目卡式进度环、整卡跳转热区，以及完整七语种今日推进文案。

- [ ] **Step 1：统一卡片高度并替换进度展示**

在 `TodayFocusCardView` 中删除项目行右侧百分比和底部横向 `ProgressView`，把三张卡片统一为：

```swift
.frame(maxWidth: .infinity, minHeight: 187, maxHeight: 187, alignment: .topLeading)
```

新增与 `OverviewProjectCard.progressRing` 参数一致的右下角组件：

```swift
private var progressRing: some View {
    let progress = max(0, min(1, item.projectProgress))

    return HStack(spacing: 12) {
        Text("\(Int(progress * 100))%")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(hex: "#00BBE1"))
            .monospacedDigit()

        ZStack {
            Circle()
                .stroke(Color(hex: "#00BBE1").opacity(0.2), lineWidth: 7)
                .frame(width: 28, height: 28)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Color(hex: "#00BBE1"), Color(hex: "#00F9D0"), Color(hex: "#00BBE1")],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 28)
        }
    }
}
```

卡片底部使用 `HStack(alignment: .bottom)`：左侧显示原因与提醒，右侧显示 `progressRing`。

- [ ] **Step 2：修正任务行对齐和整卡点击**

将任务行改为：

```swift
HStack(alignment: .center, spacing: 8) {
    Button(action: onToggle) { Image(systemName: "circle") }
        .buttonStyle(.plain)
    Text(item.taskTitle)
}
```

删除项目行、任务文字、原因行和进度区域各自的 `.onTapGesture`。在整个卡片 Surface 外层统一增加：

```swift
.contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
.onTapGesture(perform: onOpen)
```

完成圆圈继续使用原生 `Button`，由按钮消费点击并只调用 `onToggle`；不得把完成操作改成父级手势。

- [ ] **Step 3：给语言 Picker 建立独立 System 键**

将 `AppLanguage.title` 的 system 分支从通用“系统”键改为独立键：

```swift
case .system: "LanguageSystemOption"
```

七份主 App 本地化文件增加：

```text
zh-Hans: "LanguageSystemOption" = "系统";
en/ja/ko/de/fr/es: "LanguageSystemOption" = "System";
```

不得修改 `AppTheme.system`，它继续使用通用“系统”键。

- [ ] **Step 4：补齐主 App 七语种今日推进文案**

在 `Viabar/ja.lproj/Localizable.strings`、`ko`、`de`、`fr`、`es` 中增加与现有中英文相同的键集合，逐键使用下表内容：

| Key | ja | ko | de | fr | es |
|---|---|---|---|---|---|
| 今日推进 | 今日のフォーカス | 오늘의 집중 | Heute im Fokus | Priorités du jour | Enfoque de hoy |
| %d 项 | %d件 | %d개 | %d Einträge | %d éléments | %d elementos |
| 今天没有需要推进的任务 | 今日は進める必要のあるタスクはありません | 오늘 진행할 작업이 없습니다 | Heute sind keine Aufgaben voranzutreiben | Aucune tâche à faire avancer aujourd’hui | No hay tareas que avanzar hoy |
| 暂时无法读取今日推进 | 今日のフォーカスを一時的に読み込めません | 오늘의 집중을 일시적으로 불러올 수 없습니다 | „Heute im Fokus“ kann vorübergehend nicht geladen werden | Impossible de charger temporairement les priorités du jour | No se puede cargar temporalmente el enfoque de hoy |
| 提醒已逾期 | 期限切れ | 기한 지남 | Überfällig | En retard | Atrasado |
| 今天需要处理 | 今日が期限 | 오늘 마감 | Heute fällig | À faire aujourd’hui | Para hoy |
| 收藏项目 | お気に入りのプロジェクト | 즐겨찾는 프로젝트 | Favoritenprojekt | Projet favori | Proyecto favorito |
| 已 %d 天未推进 | %d日間進捗なし | %d일 동안 진행 없음 | Seit %d Tagen kein Fortschritt | Aucune progression depuis %d jours | Sin avances durante %d días |
| 按项目顺序推荐 | プロジェクト順 | 프로젝트 순서 | Projektreihenfolge | Ordre des projets | Orden del proyecto |
| AI 建议 | AIの提案 | AI 제안 | KI-Vorschlag | Suggestion de l’IA | Sugerencia de IA |
| 标记为完成 | 完了としてマーク | 완료로 표시 | Als erledigt markieren | Marquer comme terminé | Marcar como completado |
| 展示当前最值得推进的任务 | 今取り組む価値の高いタスクを表示します | 지금 가장 진행할 가치가 있는 작업을 표시합니다 | Zeigt die Aufgaben, die jetzt am wichtigsten sind | Affiche les tâches les plus importantes à faire avancer maintenant | Muestra las tareas que más conviene avanzar ahora |

- [ ] **Step 5：补齐 Widget 七语种资源**

在 `ViabarWidget` 新增 `ja.lproj`、`ko.lproj`、`de.lproj`、`fr.lproj`、`es.lproj` 的 `Localizable.strings`，写入 Step 4 的同一键集合和对应译文。`ViabarWidget` 是文件系统同步目录，新资源随 Widget targets 自动纳入；不得复制推荐逻辑或修改 Widget 视图结构。

- [ ] **Step 6：执行静态验证**

运行：

```bash
rg -n "minHeight: 187|maxHeight: 187|private var progressRing|HStack\(alignment: \.center|contentShape\(RoundedRectangle|onTapGesture\(perform: onOpen\)" Viabar/Views/Component/TodayFocusSectionView.swift
rg -n "LanguageSystemOption|case \.system: \"系统\"" Viabar/Models/AppSettings.swift Viabar/*.lproj/Localizable.strings
plutil -lint Viabar/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings
plutil -lint ViabarWidget/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings
plutil -lint Viabar.xcodeproj/project.pbxproj
git diff --check
```

预期：三张卡片固定高 `187`；项目行无百分比，底部无横向进度条；任务行使用 `.center`；整卡只有一个统一跳转手势；七种语言资源均通过 plist lint；`AppLanguage.system` 使用独立键且 `AppTheme.system` 保持原键。不编译、不运行测试、不提交。

### Task 9：收紧 macOS 今日推进卡片密度

**Files:**
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`

**Interfaces:**
- Consumes: `TodayFocusCardView` 现有项目标题、任务行、原因行和 `progressRing`。
- Produces: 固定高 `148`、两段 `12` 点垂直间距且进度环不带百分比的卡片。

- [ ] **Step 1：统一两段垂直间距并降低高度**

将卡片内容栈改为固定 `12` 点间距，删除任务行之后的 `Spacer(minLength: 0)`：

```swift
VStack(alignment: .leading, spacing: 12) {
    projectHeader
    taskRow
    bottomRow
}
.frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .topLeading)
```

保持主次推荐原有字号、内边距和 `50% / 25% / 25%` 宽度分配。

- [ ] **Step 2：移除进度环左侧百分比**

将 `progressRing` 从包含百分比的 `HStack` 收敛为单独的 `ZStack`，保留现有轨道、渐变、线宽和 `28 × 28` 尺寸：

```swift
private var progressRing: some View {
    ZStack {
        Circle().stroke(...)
        Circle().trim(...).stroke(...).rotationEffect(.degrees(-90))
    }
    .frame(width: 28, height: 28)
}
```

- [ ] **Step 3：执行静态验证**

运行：

```bash
rg -n "VStack\(alignment: \.leading, spacing: 12\)|minHeight: 148|maxHeight: 148|private var progressRing" Viabar/Views/Component/TodayFocusSectionView.swift
sed -n '156,198p' Viabar/Views/Component/TodayFocusSectionView.swift | rg -n "Spacer\(minLength: 0\)"
rg -n "projectProgress \* 100|minHeight: 187|maxHeight: 187" Viabar/Views/Component/TodayFocusSectionView.swift
git diff --check
```

预期：第一条搜索命中统一间距、固定高度和进度环；后两条搜索无输出，表示任务行与底部之间没有弹性空白、卡片不再渲染项目进度百分比且不存在旧高度；差异无空白错误。不编译、不运行测试、不提交。

### Task 10：将任务与底部信息整体下移

**Files:**
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`

**Interfaces:**
- Consumes: `projectHeader`、任务行、底部原因行和 `progressRing`。
- Produces: 项目标题固定顶部、任务与底部信息组成贴底内容组的 `TodayFocusCardView`。

- [ ] **Step 1：建立上下分组布局**

外层改为零间距布局，在项目标题和任务内容组之间插入弹性空白：

```swift
VStack(alignment: .leading, spacing: 0) {
    projectHeader
    Spacer(minLength: 12)
    taskAndFooter
}
```

卡片继续固定高 `148`，不修改内边距、圆角和整卡点击区域。

- [ ] **Step 2：保持任务组内部紧凑**

将任务行和底部原因/进度环包入固定间距内容组：

```swift
VStack(alignment: .leading, spacing: 12) {
    taskRow
    bottomRow
}
```

该内容组位于外层弹性空白之后，因此整体贴近卡片底部；任务与底部之间保持 `12` 点。

- [ ] **Step 3：执行静态验证**

运行：

```bash
rg -n "VStack\(alignment: \.leading, spacing: 0\)|Spacer\(minLength: 12\)|VStack\(alignment: \.leading, spacing: 12\)|minHeight: 148|maxHeight: 148" Viabar/Views/Component/TodayFocusSectionView.swift
git diff --check
```

预期：外层栈为零间距并在标题后包含最小 `12` 点弹性空白；任务与底部区域位于固定 `12` 点间距的内层栈；卡片仍为 `148` 点；差异无空白错误。不编译、不运行测试、不提交。

### Task 11：将任务行置于标题与底部行中间

**Files:**
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`

**Interfaces:**
- Consumes: `projectHeader`、任务行、底部原因行和 `progressRing`。
- Produces: 使用两个等权弹性间距垂直分布三层内容的 `TodayFocusCardView`。

- [ ] **Step 1：拆除任务与底部组合**

移除包裹任务行和底部行的内层 `VStack(spacing: 12)`，让任务行和底部行重新成为外层栈的独立子项。

- [ ] **Step 2：在任务行上下加入等权间距**

将外层布局调整为：

```swift
VStack(alignment: .leading, spacing: 0) {
    projectHeader
    Spacer(minLength: 8)
    taskRow
    Spacer(minLength: 8)
    bottomRow
}
```

两个 Spacer 都没有固定高度，因此平分剩余空间；任务行位于项目标题与底部行之间。卡片继续固定为 `148` 点。

- [ ] **Step 3：执行静态验证**

运行：

```bash
rg -n "VStack\(alignment: \.leading, spacing: 0\)|Spacer\(minLength: 8\)|minHeight: 148|maxHeight: 148" Viabar/Views/Component/TodayFocusSectionView.swift
git diff --check
```

预期：卡片外层仍为零间距；任务行前后恰好各有一个 `Spacer(minLength: 8)`；不存在包裹任务与底部行的内层栈；卡片仍为 `148` 点；差异无空白错误。不编译、不运行测试、不提交。

### Task 12：让 iOS 今日推进卡片对齐 macOS 信息结构

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`

**Interfaces:**
- Consumes: `IOSPersistentTodayFocusCard`、`TodayFocusItem.projectProgress`、`reasonColor` 和 `reasonText`。
- Produces: 三张全宽、固定高 `148` 且使用三层信息结构的 iOS 卡片。

- [ ] **Step 1：将完成按钮移入任务行**

把现有外层 `HStack` 改为 `VStack(alignment: .leading, spacing: 0)`。顶部只放项目图标与名称；任务行改为：

```swift
HStack(alignment: .center, spacing: 8) {
    Button(action: onToggle) { Image(systemName: "circle") }
        .buttonStyle(.plain)
    Text(item.taskTitle)
}
```

项目标题与任务行、任务行与底部行之间分别加入一个 `Spacer(minLength: 8)`。

- [ ] **Step 2：对齐底部原因和进度环**

删除原因前的实心 `Circle`、右上百分比和底部横向 `ProgressView`。增加 `reasonSymbolName`，映射与 macOS 相同的 `alarm.fill`、`star.fill`、`clock.arrow.circlepath`、`list.number`、`sparkles`。底部使用：

```swift
HStack(alignment: .bottom, spacing: 10) {
    reasonAndReminder
    Spacer(minLength: 4)
    progressRing
}
```

`progressRing` 使用 `28 × 28`、7 点线宽和现有青色渐变，不显示百分比。

- [ ] **Step 3：统一三张卡片尺寸和 iOS 表面**

将主次推荐都固定为：

```swift
.frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .topLeading)
```

保留 `Color(.secondarySystemBackground)`、14 点圆角、主题色边框、整卡 `contentShape` 和 `onTapGesture`。列表继续使用单列 `VStack`，每张卡片独占一行。

- [ ] **Step 4：执行静态验证**

运行：

```bash
rg -n "IOSPersistentTodayFocusCard|VStack\(alignment: \.leading, spacing: 0\)|Spacer\(minLength: 8\)|minHeight: 148|maxHeight: 148|private var progressRing|private var reasonSymbolName" ViabariOS/Persistence/IOSPersistentOverviewView.swift
rg -n "projectProgress \* 100|ProgressView\(value: item\.projectProgress\)|Circle\(\).*fill\(reasonColor\)" ViabariOS/Persistence/IOSPersistentOverviewView.swift
git diff --check
```

预期：iOS 三张卡片仍为单列全宽布局；卡片固定高 `148`；任务行上下各有一个 `Spacer(minLength: 8)`；不存在右上百分比、横向进度条或原因实心圆点；进度环和原因图标存在；差异无空白错误。不编译、不运行测试、不提交。

### Task 13：让 iOS 今日推荐匹配项目列表视觉系统

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `Viabar/Views/Component/TodayFocusSectionView.swift`
- Modify: `ViabarWidget/ViabarTodayFocusWidget.swift`
- Modify: `Viabar/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings`
- Modify: `ViabarWidget/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `IOSPersistentOverviewProjectCard` 的表面参数、`IOSGlassView`、`TodayFocusItem` 和现有国际化链路。
- Produces: 低于项目卡片、视觉层级一致且三端统一命名的今日推荐区域。

- [ ] **Step 1：复用项目卡片外层和内层表面**

给 `IOSPersistentTodayFocusCard` 增加 `colorScheme` 环境。外层使用项目卡片相同的 24 点圆角、渐变边框、深浅色填充、阴影、`IOSGlassView` 和暗色高光；任务区域使用相同的 20 点圆角、不透明填充和细边框。项目图标与名称保留在外层玻璃区域。

- [ ] **Step 2：降低高度和内容密度**

三张卡片统一：

```swift
.frame(height: 132)
.frame(maxWidth: .infinity, alignment: .leading)
```

项目标题使用项目卡片的 11 点图标和 12 点 bold 标题；任务字号为主推荐 13 点 medium、次推荐 12 点 medium；原因与提醒使用 11 点。进度环改为 24 点直径和 5 点线宽。

- [ ] **Step 3：让 iOS 分区标题匹配任务列表标题**

“今日推荐”和 `scope` 图标使用与 `IOSPrototypeSectionLabel` 相同的：

```swift
.font(.caption2.weight(.medium))
.foregroundStyle(.secondary)
.textCase(.uppercase)
.tracking(0.5)
```

数量文本继续通过 `AppLocalization.format("%d 项", ...)` 读取，并使用同一视觉层级。

- [ ] **Step 4：三端更名并更新七种语言**

将 macOS、iOS 和 Widget 的标题键从“今日推进”改为“今日推荐”。主 App 与 Widget 的 7 份资源分别使用：

| Locale | Value |
|---|---|
| zh-Hans | 今日推荐 |
| en | Today’s Recommendations |
| ja | 今日のおすすめ |
| ko | 오늘의 추천 |
| de | Heutige Empfehlungen |
| fr | Recommandations du jour |
| es | Recomendaciones de hoy |

保留数量、空状态、不可用状态、推荐原因和完成辅助文本的现有本地化键，不新增硬编码用户文案。

- [ ] **Step 5：执行静态验证**

运行：

```bash
rg -n "frame\(height: 132\)|cornerRadius: 24|cornerRadius: 20|IOSGlassView|font\(\.system\(size: isPrimary \? 13 : 12|frame\(width: 24, height: 24\)" ViabariOS/Persistence/IOSPersistentOverviewView.swift
rg -n "caption2\.weight\(\.medium\)|textCase\(\.uppercase\)|tracking\(0\.5\)" ViabariOS/Persistence/IOSPersistentOverviewView.swift
rg -n "今日推荐" Viabar/Views/Component/TodayFocusSectionView.swift ViabariOS/Persistence/IOSPersistentOverviewView.swift ViabarWidget/ViabarTodayFocusWidget.swift
plutil -lint Viabar/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings
plutil -lint ViabarWidget/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings
git diff --check
```

预期：iOS 今日推荐卡片为 132 点且视觉参数与项目卡片一致；任务字号和进度环更小；分区标题样式与任务列表一致；三端源码使用“今日推荐”；14 份 strings 资源格式正确且包含新标题；差异无空白错误。不编译、不运行测试、不提交。

### Task 14：移除 iOS 今日推荐的内层白卡

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`

**Interfaces:**
- Consumes: `IOSPersistentTodayFocusCard` 当前 24 点外层 Surface、项目行、任务行和底部行。
- Produces: 与 macOS 相同的单层三行布局，同时保留 iOS 项目卡片外层视觉参数。

- [ ] **Step 1：删除内层 Surface**

删除任务/底部容器上的 20 点 `RoundedRectangle` 背景、细边框、水平 6 点外缩进及上下额外边距。不得保留透明的嵌套布局壳层。

- [ ] **Step 2：恢复单层三行布局**

让外层内容直接排列为：

```swift
VStack(alignment: .leading, spacing: 0) {
    projectHeader
    Spacer(minLength: 8)
    taskRow
    Spacer(minLength: 8)
    bottomRow
}
.padding(isPrimary ? 14 : 12)
```

保留卡片固定高 `132`、24 点外层圆角、渐变边框、阴影、`IOSGlassView`、任务字号和 24 点进度环。

- [ ] **Step 3：执行静态验证**

运行：

```bash
rg -n "frame\(height: 132\)|cornerRadius: 24|IOSGlassView|Spacer\(minLength: 8\)|IOSPrototypeProgressRing" ViabariOS/Persistence/IOSPersistentOverviewView.swift
rg -n "cornerRadius: 20|padding\(\.horizontal, 6\)|mainPanelBackground : Color\.white" ViabariOS/Persistence/IOSPersistentOverviewView.swift
git diff --check
```

预期：今日推荐卡片仍保留 132 点高和外层 24 点 Surface；项目、任务、底部行位于同一个 VStack；任务上下各有一个 8 点最小弹性间距；卡片范围内没有 20 点内层圆角、白色填充或内层边框；差异无空白错误。不编译、不运行测试、不提交。

### Task 15：补齐 iOS 今日推荐和语言 System 本地化资源

**Files:**
- Modify: `ViabariOS/en.lproj/Localizable.strings`
- Modify: `ViabariOS/zh-Hans.lproj/Localizable.strings`
- Create: `ViabariOS/ja.lproj/Localizable.strings`
- Create: `ViabariOS/ko.lproj/Localizable.strings`
- Create: `ViabariOS/de.lproj/Localizable.strings`
- Create: `ViabariOS/fr.lproj/Localizable.strings`
- Create: `ViabariOS/es.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `AppLocalization.string/format`、`AppLanguage.title` 的 `LanguageSystemOption` 键和 iOS 文件系统同步资源目录。
- Produces: iOS Bundle 可读取的 7 种语言今日推荐文本及正确的 System 选项。

- [ ] **Step 1：补齐英文和简体中文**

在现有 iOS 英文和简中 strings 中增加以下 13 个键：

```text
LanguageSystemOption
今日推荐
%d 项
今天没有需要推进的任务
暂时无法读取今日推荐
提醒已逾期
今天需要处理
收藏项目
已 %d 天未推进
按项目顺序推荐
AI 建议
标记为完成
展示当前最值得推进的任务
```

英文 `LanguageSystemOption` 为 `System`，简中为“系统”。

- [ ] **Step 2：新增其余五种语言资源**

创建 `ja`、`ko`、`de`、`fr`、`es` 五份 iOS `Localizable.strings`，使用主 App 已确认的对应译文。五份资源的 `LanguageSystemOption` 都固定为 `System`。

- [ ] **Step 3：验证资源归属和键完整性**

运行：

```bash
find ViabariOS -maxdepth 2 -type f -name Localizable.strings -print | sort
plutil -lint ViabariOS/{en,zh-Hans,ja,ko,de,fr,es}.lproj/Localizable.strings
rg -n '"LanguageSystemOption" =|"今日推荐" =|"提醒已逾期" =|"%d 项" =' ViabariOS/*.lproj/Localizable.strings
git diff --check
```

预期：iOS 目标目录存在 7 份资源；每份资源包含完整且唯一的 13 个键；简中 System 选项为“系统”，其余六种语言为 `System`；所有 strings 通过 plist lint；差异无空白错误。不编译、不运行测试、不提交。
