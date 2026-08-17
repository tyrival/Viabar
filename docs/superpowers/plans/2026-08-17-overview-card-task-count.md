# 总览卡片任务数量 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在显示设置中提供 1、2、3 个总览卡片任务数量选项，并让总览卡片按该数量展示未完成任务及其首个未完成子任务，同时保持固定高度和首任务提醒语义。

**Architecture:** 新建一个不依赖 SwiftData schema 的总览卡片配置单元，集中负责数量解析、`UserDefaults` 持久化、任务截取和固定高度映射。设置页与总览卡片通过同一个 `UserDefaults` key 响应式联动；卡片只调整任务内容循环和高度，不改变现有提醒、进度、菜单及拖放链路。

**Tech Stack:** Swift 5.10+、SwiftUI、SwiftData 现有模型、Foundation `UserDefaults`、Swift Testing、本地化 `.strings`。

## Global Constraints

- 不修改 `AppSettings` 持久化字段，不触发 SwiftData schema 变更。
- 历史安装无设置值或读取到非法值时默认显示 1 个任务。
- 数量仅允许 1、2、3；每个任务只附带其第一个未完成子任务。
- 提醒仍只显示第一个未完成任务的提醒。
- 卡片高度按 1、2、3 分别固定为 187pt、235pt、283pt。
- 不改变项目进度、任务完成/排序、提醒、拖放、上下文菜单和导航语义。
- 同步更新英文和简体中文本地化。
- 用户未授权编译、运行测试或提交；执行时只允许静态检查。若要执行 TDD 的 RED/GREEN 命令，必须先获得用户明确授权。

---

## File Structure

- Create: `Viabar/Models/OverviewCardConfiguration.swift` — 定义任务数量、设置存储、任务选择和高度策略。
- Modify: `ViabarTests/ViabarTests.swift` — 覆盖默认值、非法值、持久化、任务截取和高度映射。
- Modify: `Viabar/Views/Settings/SettingsView.swift` — 新增设置行与响应式 Picker 绑定。
- Modify: `Viabar/ContentView.swift` — 按配置渲染多组任务/子任务并应用固定高度。
- Modify: `Viabar/en.lproj/Localizable.strings` — 添加英文设置文案。
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings` — 添加简体中文设置文案。

### Task 1: 总览卡片配置与持久化

**Files:**
- Create: `Viabar/Models/OverviewCardConfiguration.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: `Project.unfinishedMilestones: [Milestone]`、`UserDefaults`。
- Produces: `OverviewCardTaskCount`、`OverviewCardTaskCountSettingsStore.value(defaults:)`、`OverviewCardTaskCountSettingsStore.set(_:defaults:)`、`OverviewCardConfiguration.milestones(for:count:)`、`OverviewCardConfiguration.cardHeight(for:)`。

- [ ] **Step 1: 写入设置默认值和非法值测试**

在 `AppSettingsTests` 中加入：

```swift
@Test func overviewCardTaskCountDefaultsToOneAndPersistsValidSelection() throws {
    let suiteName = "ViabarTests.OverviewCardTaskCount.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(OverviewCardTaskCountSettingsStore.value(defaults: defaults) == .one)
    defaults.set(99, forKey: OverviewCardTaskCountSettingsStore.key)
    #expect(OverviewCardTaskCountSettingsStore.value(defaults: defaults) == .one)
    OverviewCardTaskCountSettingsStore.set(.three, defaults: defaults)
    #expect(OverviewCardTaskCountSettingsStore.value(defaults: defaults) == .three)
}
```

- [ ] **Step 2: 写入任务截取与高度测试**

在 `AppSettingsTests` 中加入：

```swift
@Test func overviewCardConfigurationSelectsUnfinishedMilestonesAndMapsFixedHeights() {
    let project = Project(title: "Project")
    let completed = Milestone(title: "Completed", orderIndex: 0, isCompleted: true)
    let first = Milestone(title: "First", orderIndex: 1)
    let second = Milestone(title: "Second", orderIndex: 2)
    let third = Milestone(title: "Third", orderIndex: 3)
    completed.project = project
    first.project = project
    second.project = project
    third.project = project
    project.milestones = [third, completed, second, first]

    #expect(OverviewCardConfiguration.milestones(for: project, count: .two).map(\.title) == ["First", "Second"])
    #expect(OverviewCardConfiguration.cardHeight(for: .one) == 187)
    #expect(OverviewCardConfiguration.cardHeight(for: .two) == 235)
    #expect(OverviewCardConfiguration.cardHeight(for: .three) == 283)
}
```

- [ ] **Step 3: 在获准运行测试时验证 RED**

Run only after explicit authorization:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/AppSettingsTests
```

Expected: FAIL，提示 `OverviewCardTaskCount`、`OverviewCardTaskCountSettingsStore` 和 `OverviewCardConfiguration` 尚未定义。

- [ ] **Step 4: 实现最小配置单元**

创建 `Viabar/Models/OverviewCardConfiguration.swift`：

```swift
import Foundation

enum OverviewCardTaskCount: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    static func resolve(_ storedValue: Int?) -> OverviewCardTaskCount {
        OverviewCardTaskCount(rawValue: storedValue ?? 1) ?? .one
    }
}

enum OverviewCardTaskCountSettingsStore {
    static let key = "overviewCardTaskCount"

    static func value(defaults: UserDefaults = .standard) -> OverviewCardTaskCount {
        OverviewCardTaskCount.resolve(defaults.object(forKey: key) as? Int)
    }

    static func set(
        _ value: OverviewCardTaskCount,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(value.rawValue, forKey: key)
    }
}

enum OverviewCardConfiguration {
    static func milestones(
        for project: Project,
        count: OverviewCardTaskCount
    ) -> [Milestone] {
        Array(project.unfinishedMilestones.prefix(count.rawValue))
    }

    static func cardHeight(for count: OverviewCardTaskCount) -> CGFloat {
        187 + CGFloat(count.rawValue - 1) * 48
    }
}
```

- [ ] **Step 5: 在获准运行测试时验证 GREEN**

Run only after explicit authorization:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/AppSettingsTests
```

Expected: PASS。

### Task 2: 设置页 Picker 与本地化

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `OverviewCardTaskCount.allCases`、`OverviewCardTaskCountSettingsStore.key`。
- Produces: 使用同一 `UserDefaults` key 的响应式设置 Picker。

- [ ] **Step 1: 在设置详情视图声明响应式存储值**

与 `isTodayFocusVisible` 相邻加入：

```swift
@AppStorage(OverviewCardTaskCountSettingsStore.key)
private var storedOverviewCardTaskCount = OverviewCardTaskCount.one.rawValue
```

- [ ] **Step 2: 在“视图”分组增加设置行**

紧跟现有“总览”范围行之后加入分隔线和 Picker：

```swift
SettingsDivider()
SettingsRow("总览卡片任务数量") {
    Picker("总览卡片任务数量", selection: overviewCardTaskCountBinding) {
        ForEach(OverviewCardTaskCount.allCases) { count in
            Text("\(count.rawValue)").tag(count)
        }
    }
    .labelsHidden()
    .controlSize(.small)
    .frame(width: 150, alignment: .trailing)
}
```

- [ ] **Step 3: 增加 Picker Binding**

与 `overviewScopeBinding` 相邻加入：

```swift
private var overviewCardTaskCountBinding: Binding<OverviewCardTaskCount> {
    Binding(
        get: { OverviewCardTaskCount.resolve(storedOverviewCardTaskCount) },
        set: { storedOverviewCardTaskCount = $0.rawValue }
    )
}
```

- [ ] **Step 4: 增加中英文本地化**

在两个资源文件的“视图/总览”附近分别加入：

```text
// Viabar/zh-Hans.lproj/Localizable.strings
"总览卡片任务数量" = "总览卡片任务数量";

// Viabar/en.lproj/Localizable.strings
"总览卡片任务数量" = "Tasks per Overview Card";
```

### Task 3: 总览卡片多任务布局

**Files:**
- Modify: `Viabar/ContentView.swift`

**Interfaces:**
- Consumes: `OverviewCardTaskCountSettingsStore.key`、`OverviewCardTaskCount.resolve(_:)`、`OverviewCardConfiguration.milestones(for:count:)`、`OverviewCardConfiguration.cardHeight(for:)`。
- Produces: 固定高度的 1/2/3 任务总览卡片。

- [ ] **Step 1: 让总览卡片订阅数量设置**

在 `OverviewProjectCard` 的查询/状态属性附近加入：

```swift
@AppStorage(OverviewCardTaskCountSettingsStore.key)
private var storedTaskCount = OverviewCardTaskCount.one.rawValue
```

并加入派生属性：

```swift
private var taskCount: OverviewCardTaskCount {
    OverviewCardTaskCount.resolve(storedTaskCount)
}

private var displayedMilestones: [Milestone] {
    OverviewCardConfiguration.milestones(for: project, count: taskCount)
}

private var cardHeight: CGFloat {
    OverviewCardConfiguration.cardHeight(for: taskCount)
}
```

保留 `topMilestone = project.unfinishedMilestones.first`，确保提醒仍来自首个任务。

- [ ] **Step 2: 让 hover 状态区分不同任务和子任务**

将 `HoveredText` 改为携带 ID：

```swift
private enum HoveredText: Equatable {
    case project
    case milestone(UUID)
    case subtask(UUID)
}
```

任务颜色判断使用 `.milestone(milestone.milestoneId)`，子任务颜色判断使用 `.subtask(subtask.taskId)`，对应 `onHover` 写入同一枚举值。

- [ ] **Step 3: 把单任务内容替换为固定高度任务组循环**

用以下结构替换 `if let milestone = topMilestone` 内容：

```swift
ForEach(displayedMilestones) { milestone in
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 12))
                .foregroundStyle(Color.gray.opacity(0.55))
                .frame(width: 16, alignment: .center)
            Text(milestone.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    milestoneTitleColor(
                        milestone.markerColor,
                        isHovered: hoveredText == .milestone(milestone.milestoneId)
                    )
                )
                .lineLimit(1)
        }
        .padding(.leading, taskRowIndent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover {
            hoveredText = $0 ? .milestone(milestone.milestoneId) : nil
        }

        if let subtask = milestone.subtasks
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .first(where: { !$0.isCompleted }) {
            Text(subtask.title)
                .font(.system(size: 12))
                .foregroundStyle(
                    subtaskTitleColor(
                        subtask.markerColor,
                        isHovered: hoveredText == .subtask(subtask.taskId)
                    )
                )
                .lineLimit(1)
                .padding(.leading, taskRowIndent + 22)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onHover {
                    hoveredText = $0 ? .subtask(subtask.taskId) : nil
                }
        }
    }
    .frame(height: 48, alignment: .top)
}
```

- [ ] **Step 4: 应用按数量映射的固定卡片高度**

将：

```swift
.frame(height: 187)
```

替换为：

```swift
.frame(height: cardHeight)
```

保留任务列表之后、提醒/进度之前的 `Spacer(minLength: 0)`，保证未完成任务少于设置数量时底部区域仍对齐。

### Task 4: 静态验证与差异审查

**Files:**
- Verify: `Viabar/Models/OverviewCardConfiguration.swift`
- Verify: `Viabar/Views/Settings/SettingsView.swift`
- Verify: `Viabar/ContentView.swift`
- Verify: `Viabar/en.lproj/Localizable.strings`
- Verify: `Viabar/zh-Hans.lproj/Localizable.strings`
- Verify: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 的完整差异。
- Produces: 不编译条件下的静态验证证据。

- [ ] **Step 1: 检查设置 key、默认值和合法选项**

```bash
rg -n "overviewCardTaskCount|OverviewCardTaskCount|case one = 1|case two = 2|case three = 3" Viabar ViabarTests --glob '*.swift'
```

Expected: 配置文件、设置页、卡片和测试共同引用同一 key；枚举只有 1、2、3。

- [ ] **Step 2: 检查卡片任务、子任务、提醒和高度链路**

```bash
rg -n "displayedMilestones|prefix\(count.rawValue\)|first\(where: \{ !\$0.isCompleted \}\)|topMilestone|displayedMilestoneReminder|cardHeight" Viabar/Models/OverviewCardConfiguration.swift Viabar/ContentView.swift
```

Expected: 任务受数量限制；每个任务只取首个未完成子任务；提醒仍源于 `topMilestone`；高度来自配置映射。

- [ ] **Step 3: 检查本地化语法**

```bash
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

Expected: 两个文件均返回 `OK`。

- [ ] **Step 4: 检查格式与范围**

```bash
git diff --check
git diff -- Viabar/Models/OverviewCardConfiguration.swift Viabar/Views/Settings/SettingsView.swift Viabar/ContentView.swift Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings ViabarTests/ViabarTests.swift
git status --short
```

Expected: `git diff --check` 无输出；差异仅包含本需求和已确认文档；不出现 SwiftData schema、Widget 或备份相关改动。

## Execution Note

本计划不包含提交步骤，因为用户未授权提交。当前也未授权编译或运行测试，因此 Task 1 的 RED/GREEN 命令只能在用户明确授权后执行；若用户继续要求静态实现，则保留测试代码但不运行，并在交付时明确说明未验证项。
