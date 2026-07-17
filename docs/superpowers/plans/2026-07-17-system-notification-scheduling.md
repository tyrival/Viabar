# Viabar macOS 系统通知调度实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 macOS 提醒从 App 内主线程 Timer 改为系统持有的日期触发通知，并保证独立提醒、错过提醒、重复周期和完成取消符合已确认语义。

**Architecture:** `NotificationScheduleService` 继续维护 SwiftData 展示条目，但实际投递通过注入的 `UserNotificationCenterClient` 注册稳定 identifier 的 `UNCalendarNotificationTrigger`。服务在启动、Mac 唤醒和 App 激活时对账系统 pending/delivered 状态；`ProjectService` 成为提醒同步和任务完成的唯一业务入口。

**Tech Stack:** Swift 5.10+、SwiftUI、SwiftData、UserNotifications、AppKit、macOS 14.0+、Apple 原生框架。

## Global Constraints

- 使用中文交流。
- 用户未明确要求时不编译、不运行测试；计划中的测试命令仅在用户明确授权后运行。
- 不提交代码。
- 不修改任何 `@Model`、SwiftData schema、数据库路径、备份格式或 CloudKit 配置。
- 多个不同错过提醒只补时间最近的一条；同一个重复提醒错过多个周期时也只补最近一次。
- 一次性提醒最多投递一次，后续同步不得重复注册。
- `NotificationScheduleEntry` 保留为展示数据，不再充当运行时定时器。
- 实施只触及通知调度及其直接调用链，不进行无关重构。

---

## 文件结构

- 新建 `Viabar/Services/UserNotificationCenterClient.swift`：封装系统通知中心异步 API，并提供可注入协议。
- 修改 `Viabar/Services/NotificationScheduleService.swift`：稳定 identifier、系统请求、同步、取消和生命周期对账。
- 修改 `Viabar/Models/ReminderDisplay.swift`：计算重复提醒最近错过周期。
- 修改 `Viabar/Services/ProjectService.swift`：统一完成、提醒更新、删除和归档通知链路。
- 修改 `Viabar/Views/MainPanel/MilestoneListView.swift`：移除 View 层重复通知同步。
- 修改 `Viabar/ViabarApp.swift`：接入 App 激活和 Mac 唤醒对账。
- 修改 `ViabarTests/ViabarTests.swift`：使用内存 fake 验证生命周期语义。

---

### Task 1：建立可测试的系统通知中心边界

**Files:**
- Create: `Viabar/Services/UserNotificationCenterClient.swift`
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: `UNUserNotificationCenter`、`UNNotificationRequest`、`UNAuthorizationStatus`。
- Produces: `@MainActor protocol UserNotificationCenterClient`、`SystemUserNotificationCenterClient`、可注入的通知服务初始化方法。

- [ ] **Step 1：增加测试 fake**

在通知生命周期测试区域定义：

```swift
@MainActor
final class FakeUserNotificationCenterClient: UserNotificationCenterClient {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var pending: [String: UNNotificationRequest] = [:]
    var deliveredIdentifiers: Set<String> = []
    var addedIdentifiers: [String] = []
    var removedPendingIdentifiers: [String] = []
    var removedDeliveredIdentifiers: [String] = []
    var addError: Error?

    func currentAuthorizationStatus() async -> UNAuthorizationStatus { authorizationStatus }
    func requestAuthorization() async throws -> Bool { true }
    func setCategories(_ categories: Set<UNNotificationCategory>) {}
    func add(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        pending[request.identifier] = request
        addedIdentifiers.append(request.identifier)
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func deliveredRequestIdentifiers() async -> Set<String> { deliveredIdentifiers }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        identifiers.forEach { pending.removeValue(forKey: $0) }
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        identifiers.forEach { deliveredIdentifiers.remove($0) }
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }
}
```

- [ ] **Step 2：定义生产协议与适配器**

创建：

```swift
import UserNotifications

@MainActor
protocol UserNotificationCenterClient: AnyObject {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func deliveredRequestIdentifiers() async -> Set<String>
    func removePendingRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}
```

`SystemUserNotificationCenterClient` 分别转发到 `notificationSettings()`、`requestAuthorization`、`add`、`pendingNotificationRequests()`、`deliveredNotifications()` 和两个精确删除 API。

- [ ] **Step 3：注入 client 并统一注册 category**

通知服务初始化改为：

```swift
init(
    modelContext: ModelContext,
    notificationCenter: any UserNotificationCenterClient = SystemUserNotificationCenterClient()
)
```

category 仅在 `start()` 注册一次；删除每次投递时重复注册 category 的逻辑。测试 helper 返回 fake 供断言。

- [ ] **Step 4：静态检查**

```bash
rg -n "protocol UserNotificationCenterClient|SystemUserNotificationCenterClient|deliveredRequestIdentifiers" Viabar ViabarTests --glob '*.swift'
git diff --check
```

预期：协议、生产实现和 fake 均存在，格式检查无输出。

---

### Task 2：注册稳定 identifier 的系统日期通知

**Files:**
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: Task 1 的 client、现有 `Reminder.fireTimestamp`、`Project.topUnfinishedTitle`。
- Produces: 稳定请求 identifier 和 owner 级 `syncProject`、`syncMilestone`、`syncSubTask`。

- [ ] **Step 1：写独立里程碑失败测试**

增加 `secondMilestoneReminderSchedulesWithoutCompletingFirstMilestone()`：创建两个未完成里程碑，只给第二个设置未来提醒，断言 pending 中存在：

```swift
"viabar.milestone.\(second.milestoneId.uuidString)"
```

并断言 trigger 是 `UNCalendarNotificationTrigger`、`repeats == false`、`nextTriggerDate() != nil`。另断言 project/milestone/subtask identifier 不冲突。

- [ ] **Step 2：仅在用户授权后运行失败测试**

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/NotificationScheduleLifecycleTests
```

预期：旧实现因随机 identifier 和 `trigger: nil` 失败。未授权时跳过并记录“未运行”。

- [ ] **Step 3：实现稳定标识和请求构造**

定义：

```swift
enum NotificationOwnerKind: String {
    case project
    case milestone
    case subtask
}

private func requestIdentifier(ownerKind: NotificationOwnerKind, ownerId: UUID) -> String {
    "viabar.\(ownerKind.rawValue).\(ownerId.uuidString)"
}
```

请求 content 保留 `ownerId`、`ownerKind`、`projectId`，并增加 `fireTimestamp`。trigger 使用完整年月日时分秒及时区：

```swift
var components = Calendar.current.dateComponents(
    [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
    from: fireDate
)
components.nanosecond = nil
let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
```

- [ ] **Step 4：把同步改为替换单个系统请求**

`syncEntry` 只执行：

1. 重建该 owner 的展示条目。
2. 取消相同稳定 identifier 的 pending request。
3. 若归档、完成、无提醒、无日期或一次性提醒已处理则停止。
4. 若日期在未来，异步 `add(request)`。
5. 注册失败记录 identifier、owner 和 fireDate，不删除业务提醒。

禁止调用全局到期扫描。

- [ ] **Step 5：删除旧 Timer 投递路径**

删除 `timer`、`scheduleNextTimer()`、生产路径的随机 UUID request identifier，以及 `syncEntry` 内的 `processDueEntries()`。未来提醒禁止使用 `trigger: nil`。

- [ ] **Step 6：静态检查**

```bash
rg -n "UNCalendarNotificationTrigger|viabar\.(project|milestone|subtask)" Viabar/Services/NotificationScheduleService.swift ViabarTests/ViabarTests.swift
rg -n "Timer|scheduledTimer|processDueEntries" Viabar/Services/NotificationScheduleService.swift
git diff --check
```

预期：日期 trigger 和稳定前缀存在；Timer 与旧扫描入口不存在。

---

### Task 3：实现启动、唤醒和激活对账

**Files:**
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Modify: `Viabar/Models/ReminderDisplay.swift`
- Modify: `Viabar/ViabarApp.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: pending/delivered 系统状态、`Reminder.nextFutureFireDate(after:now:)`。
- Produces: `reconcile(now:) async`、`latestMissedFireDate(now:calendar:)`。

- [ ] **Step 1：写四个失败测试**

增加：

```swift
@Test func reconcileBackfillsEachDistinctMissedReminderOnce() async throws
@Test func reconcileDoesNotBackfillDeliveredSingleReminderAgain() async throws
@Test func reconcileBackfillsOnlyLatestMissedCycleForRepeatingReminder() async throws
@Test func reconcileRegistersNextFutureCycleAfterBackfill() async throws
```

断言两个不同 owner 各补一条；delivered identifier 阻止一次性提醒再补；重复提醒只补最近周期；最终 `fireTimestamp > now` 且存在下一未来 pending request。

- [ ] **Step 2：仅在授权后运行测试确认失败**

使用 Task 2 的窄范围命令。预期：`reconcile(now:)` 尚不存在。

- [ ] **Step 3：生成统一候选**

定义非持久化候选：

```swift
private struct ReminderCandidate {
    let ownerId: UUID
    let ownerKind: NotificationOwnerKind
    let project: Project
    let title: String
    let body: String
    let isCompleted: Bool
    let reminder: Reminder
}
```

枚举未归档项目、里程碑和子任务。项目提醒 body 继续使用当前 `topUnfinishedTitle`；已完成 owner 和没有下一步的项目提醒不进入有效候选。

- [ ] **Step 4：实现一次性对账**

规则固定为：

```swift
if fireDate > now {
    await ensureFutureRequest(...)
} else if reminder.lastTriggeredTimestamp == nil,
          !deliveredIDs.contains(identifier) {
    try await deliverMissedNotification(...)
    reminder.lastTriggeredTimestamp = fireDate
}
```

补发可使用 `trigger: nil`，但只能存在于明确命名的 `deliverMissedNotification`。add 成功后才写触发状态；失败则保留重试条件。

- [ ] **Step 5：实现重复提醒最近周期**

在 `ReminderDisplay.swift` 增加：

```swift
func latestMissedFireDate(now: Date, calendar: Calendar = .current) -> Date?
```

从当前 `fireTimestamp` 按现有 `nextCycle` 推进，返回 `<= now` 的最后一个周期；若该周期不晚于 `lastTriggeredTimestamp` 则不补发。随后调用 `nextFutureFireDate(after:now:)` 写回第一个未来时间并注册下一请求。

- [ ] **Step 6：精确清理失效请求**

pending 中以 `viabar.` 开头但不属于有效候选的 identifier 使用 `removePendingRequests(withIdentifiers:)` 删除。禁止 `removeAllPendingNotificationRequests()`。

- [ ] **Step 7：接入生命周期**

`start()` 完成授权后调用一次 `reconcile()`。在 App active 时再次调用。服务监听 `NSWorkspace.didWakeNotification`，回调路由到同一 `reconcile()`；释放时移除 observer。

- [ ] **Step 8：静态检查**

```bash
rg -n "func reconcile|didWakeNotification|scenePhase|latestMissedFireDate" Viabar ViabarTests --glob '*.swift'
rg -n "removeAllPendingNotificationRequests" Viabar --glob '*.swift'
git diff --check
```

预期：三个生命周期入口复用同一对账方法，没有全量清空系统请求。

---

### Task 4：统一完成、删除、归档和提醒编辑链路

**Files:**
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Modify: `Viabar/Services/ProjectService.swift`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: 稳定 identifier、owner 级同步。
- Produces: 精确取消接口和统一通知 action 完成入口。

- [ ] **Step 1：写回归测试**

增加：

```swift
@Test func completingSubTaskCancelsItsPendingRequestAndUpdatesParent() async throws
@Test func completingMilestoneCancelsMilestoneAndChildRequests() async throws
@Test func archivingProjectCancelsEveryProjectRequest() async throws
@Test func completingUnrelatedTaskDoesNotRescheduleConsumedSingleReminder() async throws
@Test func notificationCompleteActionUsesProjectCompletionSemantics() async throws
```

最后一项必须断言完成最后一个子任务后父里程碑同步完成。

- [ ] **Step 2：仅在授权后运行失败测试**

运行窄范围通知测试。预期：旧通知 action 复制状态修改且完成路径会全项目重扫。

- [ ] **Step 3：实现精确取消接口**

提供：

```swift
func cancelMilestone(_ milestone: Milestone, removeDelivered: Bool = false)
func cancelSubTask(_ subTask: SubTask, removeDelivered: Bool = false)
func cancelProject(_ project: Project, removeDelivered: Bool = false)
```

`cancelProject` 计算项目及全部任务稳定 identifier；删除展示条目并取消 pending。启动对账不清除通知中心历史。

- [ ] **Step 4：收窄 ProjectService 完成范围**

里程碑完成时取消自身和联动完成的子任务请求；撤销完成时仅重建仍有效的未来提醒。子任务完成时只同步该子任务、父里程碑和项目级提醒。完成入口不再调用全项目 `syncReminderTimeline(for:)`。

- [ ] **Step 5：通知 action 走 ProjectService**

服务注册后配置完成 handler，由 `ProjectService` 查找 milestone/subtask 并调用统一完成方法。通知服务删除直接写 `isCompleted` 和 `completedAt` 的实现。项目级通知收到完成 action 时明确忽略。

- [ ] **Step 6：移除 View 层重复同步**

删除 `MilestoneListView` 在 `ProjectService.toggle...` 之后的：

```swift
syncMilestoneAndSubTaskReminders(milestone)
syncSubTaskReminder(subtask, project: project)
syncMilestoneReminder(milestone, project: project)
```

提醒 Binding 仍只调用 `ProjectService.updateReminder`。

- [ ] **Step 7：处理显式编辑**

替换提醒时取消旧 pending、移除相同 identifier 的旧 delivered 通知、保持新 Reminder 的 `lastTriggeredTimestamp == nil`，然后注册新未来请求或保留新的过期展示状态。

- [ ] **Step 8：静态检查**

```bash
rg -n "syncReminderTimeline\(for:" Viabar/Services/ProjectService.swift
rg -n "toggleMilestoneComplete|toggleSubTaskComplete|syncMilestoneAndSubTaskReminders" Viabar/Views/MainPanel/MilestoneListView.swift Viabar/Services/ProjectService.swift
rg -n "isCompleted = true|completedAt = Date\(\)" Viabar/Services/NotificationScheduleService.swift
git diff --check
```

预期：完成路径不再全项目同步，通知服务不复制任务完成业务。

---

### Task 5：恢复、授权和失败兼容

**Files:**
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Modify: `Viabar/Services/BackupService.swift` only if async call-site adaptation is required
- Modify: `Viabar/Services/TrashService.swift` only if async call-site adaptation is required
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: 现有 `rebuildTimeline(from:)`、回收站恢复调用和授权状态。
- Produces: 幂等 rebuild 与拒绝授权安全行为。

- [ ] **Step 1：写失败测试**

增加：

```swift
@Test func rebuildRestoresFutureSystemRequestsWithoutImmediateDelivery() async throws
@Test func deniedAuthorizationKeepsReminderAndScheduleEntry() async throws
@Test func notificationAddFailureLeavesReminderRetryable() async throws
```

注册失败时 Reminder 和展示条目仍存在，`lastTriggeredTimestamp` 不得提前更新。

- [ ] **Step 2：改造 rebuild**

`rebuildTimeline(from:)` 只重建展示条目、精确清理失效 Viabar pending、注册未来请求，并在循环结束后调用一次 `reconcile`。不得在 owner 循环内反复对账。

- [ ] **Step 3：处理授权**

`start()` 先读取状态：`.notDetermined` 才请求权限；`.authorized/.provisional/.ephemeral` 直接对账；`.denied` 保留业务提醒和展示条目但不注册系统请求。未知状态安全退出并记录。

- [ ] **Step 4：适配恢复调用点**

如果 rebuild 改为 async，备份和回收站恢复必须在数据库保存完成后通过主 actor 调用。不得改变备份 JSON 字段、恢复验证或数据删除顺序。

- [ ] **Step 5：静态检查数据库边界**

```bash
rg -n "@Model|Schema\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "BackupSnapshot|decodeIfPresent|init\(from decoder" Viabar ViabarTests --glob '*.swift'
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
```

预期：没有模型字段或备份格式变化，plist lint 通过。

---

### Task 6：最终验证和差异审查

**Files:**
- Review: `Viabar/Services/UserNotificationCenterClient.swift`
- Review: `Viabar/Services/NotificationScheduleService.swift`
- Review: `Viabar/Models/ReminderDisplay.swift`
- Review: `Viabar/Services/ProjectService.swift`
- Review: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Review: `Viabar/ViabarApp.swift`
- Review: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: Tasks 1–5。
- Produces: 静态检查证据，以及仅在用户授权时产生的测试/编译结果。

- [ ] **Step 1：检查旧调度器退出生产路径**

```bash
rg -n "Timer|scheduledTimer|processDueEntries|notificationPoster" Viabar/Services/NotificationScheduleService.swift Viabar/Services/ProjectService.swift
rg -n "trigger: nil" Viabar/Services/NotificationScheduleService.swift
```

预期：Timer、旧扫描和 poster 不存在；`trigger: nil` 若存在，只位于错过提醒补发函数。

- [ ] **Step 2：检查稳定 identifier 和精确取消**

```bash
rg -n "viabar\.(project|milestone|subtask)|removePendingRequests|removeDeliveredNotifications" Viabar ViabarTests --glob '*.swift'
```

预期：创建、修改、完成、删除、归档和测试使用同一规则。

- [ ] **Step 3：执行允许的静态检查**

```bash
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

预期：全部通过；没有新增文案时本地化文件无需修改。

- [ ] **Step 4：仅在明确授权后运行窄范围测试**

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/NotificationScheduleLifecycleTests
```

预期：通知生命周期测试全部通过。未授权时报告“未运行测试”。

- [ ] **Step 5：仅在明确授权后编译**

运行项目现有 macOS 构建命令。预期：主 App 构建成功；未授权时报告“未编译”。

- [ ] **Step 6：复核最终范围**

```bash
git status --short
git diff --stat
git diff -- Viabar/Services/UserNotificationCenterClient.swift Viabar/Services/NotificationScheduleService.swift Viabar/Models/ReminderDisplay.swift Viabar/Services/ProjectService.swift Viabar/Views/MainPanel/MilestoneListView.swift Viabar/ViabarApp.swift ViabarTests/ViabarTests.swift
```

预期：只有通知相关源码、测试、设计和计划文档变化，不包含 `.build`、数据库或用户数据。
