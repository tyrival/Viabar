# Viabar macOS 系统通知调度设计

## 背景

当前 `NotificationScheduleService` 使用 App 进程内的主线程 `Timer` 判断提醒是否到期，随后以 `trigger: nil` 立即提交通知。该实现会在 App 退出、Mac 休眠或重启时停止推进，并可能在 App 恢复或任务完成触发全量同步时集中投递过期通知。

另外，一次性里程碑和子任务提醒触发后仍保留过去的 `fireTimestamp`。后续同步会重新创建过期条目并再次投递，造成重复通知。

本设计将通知时间交给 macOS `UNUserNotificationCenter` 管理，使行为接近系统“提醒事项”：系统负责按时投递，Viabar 负责提醒业务状态、请求更新、取消和启动对账。

## 已确认的产品语义

1. 项目、里程碑和子任务的提醒互相独立。后续里程碑的独立提醒不依赖前序任务完成。
2. 项目级提醒仍执行上下文穿透，通知内容显示项目当前最顶端的未完成里程碑或子任务。
3. 多个不同提醒在休眠或关机期间错过时，只补发时间最近的一条通知。
4. 同一个重复提醒错过多个周期时，只显示最近错过的一条，不补发该提醒的全部历史周期。
5. 同一个一次性提醒最多投递一次。后续任务完成、标题更新、启动对账或时间线同步都不能使它重复投递。
6. 完成、删除或归档目标后，取消其尚未投递的系统通知。
7. 一次性提醒到期后可以继续在 App 内显示为已过期，但不得再次注册为系统通知；用户调整提醒时间后视为新的调度。

## 架构

### 系统通知是真正的调度器

每个有效提醒直接注册为带触发时间的 `UNNotificationRequest`：

- 一次性提醒使用包含完整年月日时分的 `UNCalendarNotificationTrigger`，`repeats: false`。
- 重复提醒不直接依赖无限重复 trigger。Viabar 只注册“下一次”确定日期的非重复请求，从而能统一处理项目级动态文案、跳过多个错过周期以及完成后的取消。
- App 启动、Mac 唤醒和 App 重新激活时执行对账，为重复提醒推进下一次系统请求。这样可以保持现有“每 2 天、每 3 天、每两周、每 3 个月”等锚定周期语义；这些周期无法全部由单个重复 Calendar trigger 精确表达。
- 不再使用 App 内 `Timer` 作为通知到期执行器。
- 不再通过扫描 `fireDate <= now` 后提交 `trigger: nil` 来正常投递未来通知。

### 稳定请求标识

系统请求 identifier 必须稳定、可计算：

```text
viabar.project.<projectId>
viabar.milestone.<milestoneId>
viabar.subtask.<taskId>
```

同一业务提醒始终使用同一 identifier。修改提醒时先取消旧 pending request，再添加新请求；完成、删除和归档时可直接按 identifier 精确取消。

通知的 `userInfo` 保留 `ownerId`、`ownerKind` 和 `projectId`，供“完成”操作和导航使用。

### 数据职责

- `Reminder`：提醒业务真相源，保存类型、业务触发时间、重复间隔和最近触发记录。
- `NotificationScheduleEntry`：继续服务概览报表和提醒时间线展示，不再承担进程内定时执行职责。
- `UNUserNotificationCenter` pending requests：系统实际待投递队列。

本次不增加、删除或修改 SwiftData 持久化字段，不属于 schema 变更。

## 调度规则

### 创建或修改提醒

1. 保存 `Reminder`。
2. 删除该 owner 的旧 `NotificationScheduleEntry`，建立最新展示条目。
3. 取消相同稳定 identifier 的系统 pending request。
4. 若目标未完成、项目未归档且存在未来触发时间，注册新的系统请求。
5. 若一次性触发时间已经过去，只保留 App 内过期状态，不在普通编辑同步中立即补发。

用户明确把提醒时间从过去调整到新的未来时间时，应清除旧的触发状态并注册新请求。

### 正常系统投递

系统按 trigger 投递通知，不要求 Viabar 正在运行。前台投递仍通过 `willPresent` 显示 banner、声音和通知列表。

App 后续进入前台或启动对账时，根据系统 delivered notifications 和提醒状态更新 `lastTriggeredTimestamp`。该字段用于防止一次性提醒被重新注册，而不是作为通知投递器。

### 启动对账

启动完成授权检查后执行一次对账；Mac 唤醒和 App 重新激活时复用同一入口：

1. 获取系统 pending requests 和 delivered notifications。
2. 获取所有未归档项目的有效提醒。
3. 取消 owner 已完成、已删除、项目已归档或数据库中已无提醒的 pending requests。
4. 为缺失的未来提醒补建系统请求。
5. 对一次性错过提醒：仅当该提醒从未投递、系统 pending 和 delivered 中均不存在对应 identifier 时，补发一条。
6. 对重复错过提醒：计算不晚于当前时间的最近一次周期，只补发该次；随后计算并注册下一次未来请求。
7. 多个不同 owner 的错过提醒只补发时间最近的一条，其余标记为已处理。
8. 对账完成后保存更新过的 `lastTriggeredTimestamp`、重复提醒下一次时间及展示条目。

补发请求仍使用稳定 identifier。补发后立即记录已处理状态，防止同一轮或下一轮对账重复补发。

### 重复提醒推进

重复提醒每次只维护一个下一次未来请求：

- 若上次计划时间仍在未来，保持或修复该请求。
- 若已经错过一个或多个周期，计算最近错过周期并最多补发一条。
- 从最近错过周期向后计算第一个未来时间，写回 `fireTimestamp` 并注册下一请求。
- 不为每个历史周期创建通知。

由于系统公开 API 不能为所有现有自定义周期持续计算后续日期，Viabar 必须至少在启动、唤醒或重新激活时推进这类重复提醒。已经交给系统的下一次请求不依赖 App 运行；该次投递之后，若 App 长期保持退出且没有再次启动，后续自定义周期无法继续滚动注册。这是公开本地通知能力边界，不通过主线程 Timer 或通知风暴补偿掩盖。

### 完成、删除与归档

- 完成里程碑：取消里程碑及其被联动完成的子任务 pending requests。
- 完成子任务：取消该子任务 pending request，并更新所属里程碑及项目级提醒。
- 删除任务：取消该任务及其子树的 pending requests。
- 归档项目：取消项目内所有 pending requests。
- 恢复、撤销完成或取消归档：只为仍有效的未来提醒重新建立请求，不补发已处理的一次性提醒。

## 项目级提醒

项目级提醒与任务级提醒使用相同的系统调度机制，但通知正文在每次注册时通过 `project.topUnfinishedTitle` 生成。

任务完成导致“下一步”变化时，仅替换项目级 pending request 的内容和触发条件，不重扫并投递项目内其他提醒。若项目级一次性提醒已经投递，则后续任务完成不应重新注册它。

## 完成操作统一入口

App 内完成按钮、菜单栏完成操作和通知 action 必须最终走同一套完成业务入口，以保证：

- `completedAt` 与父里程碑完成状态一致。
- 对应系统 pending request 被取消。
- 项目级提醒文案按新的下一步更新。
- Widget 时间线按现有机制刷新。

移除 View 层在 `ProjectService.toggle...` 已经同步后再次直接调用通知服务的重复同步。通知服务不应由 View 同时维护第二套业务流程。

## 授权与错误处理

- 启动时读取通知授权状态；仅在尚未决定时请求授权。
- 用户拒绝授权时保留 Reminder 和展示条目，不删除业务提醒；UI 可继续显示提醒状态。
- `UNUserNotificationCenter.add` 的错误不能静默丢弃，应记录包含 owner、identifier 和触发时间的诊断信息。
- 对账失败不删除 Reminder，不进行全量清空重建；下一次启动或前台恢复时可重试。
- 注册 category 在服务启动时统一执行一次，不在每次投递时重复注册。

## 主要代码边界

主要修改集中在：

- `Viabar/Services/NotificationScheduleService.swift`
- `Viabar/Services/ProjectService.swift`
- `Viabar/Views/MainPanel/MilestoneListView.swift`
- 必要的通知调度单元测试

备份恢复和回收站恢复继续调用通知服务的公开同步入口；公开入口内部改为维护系统请求，不要求调用方了解系统调度细节。

## 静态与行为验证

需要覆盖以下场景：

1. 只有第 2 个里程碑有提醒，第 1 个未完成时，第 2 个仍拥有独立系统请求。
2. 一次性提醒投递后，完成另一个任务不会再次创建或投递该提醒。
3. 多个不同 owner 的提醒均错过时，只补发时间最近的一条。
4. 同一重复提醒错过多个周期时只补发最近一条，并注册下一次未来请求。
5. 完成、删除和归档会取消对应 pending requests。
6. 修改时间使用相同稳定 identifier 替换旧请求。
7. App 启动对账不会清除仍有效的系统请求，也不会重复补发 delivered 通知。
8. 通知 action 完成子任务时同步父里程碑，并更新项目级提醒。
9. 通知权限拒绝或注册失败不会删除业务提醒。
10. `NotificationScheduleEntry` 仍能向概览报表提供正确的未来或过期提醒信息。

按仓库约束，实施后的默认验证以源码检查、通知服务的窄范围逻辑检查、`git diff --check` 和 plist/string lint 为主；只有用户明确授权时才编译或运行测试。

## 非目标

- 不启用 CloudKit。
- 不修改 SwiftData schema。
- 不增加新的提醒层级或第三层任务结构。
- 不实现位置提醒、共享提醒列表或自然语言日期解析。
- 不复制 macOS“提醒事项”的全部功能，只对齐可靠的系统定时投递和错过提醒语义。
