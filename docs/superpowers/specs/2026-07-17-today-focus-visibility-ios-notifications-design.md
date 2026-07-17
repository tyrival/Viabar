# 今日推荐显示开关与 iOS 系统通知设计

## 目标

1. macOS 在“设置 → 显示 → 视图”的第一项增加“今日推荐”开关。
2. iOS 在“设置 → 显示”增加同名开关。
3. 两个平台各自保存开关状态，不进行跨设备同步。
4. iOS 采用与 macOS 一致的 `UserNotifications` 系统调度模型，并适配各自的生命周期事件。

## 今日推荐显示设置

- 新增共享的 `TodayFocusVisibilitySettingsStore`，使用 `UserDefaults.standard`。
- 默认值为开启，保证升级后维持当前总览行为。
- macOS 与 iOS 虽复用相同代码和 key，但各自运行在独立 App 容器，因此状态各自保存。
- 不修改 `AppSettings` 或任何 SwiftData 模型，不涉及 schema、备份或恢复格式变更。
- 两端总览仅在设置开启时创建并显示今日推荐区域；关闭后不显示标题、空状态或推荐卡片。

## 设置界面

- macOS：在现有“视图”设置组首行加入“今日推荐”与原生 Switch，沿用当前设置行样式。
- iOS：在现有“显示”Section 中加入“今日推荐”Toggle，沿用当前本地化和表单样式。
- 新增用户可见文案同步维护 macOS 与 iOS 的英文、简体中文本地化资源。

## iOS 通知架构

- 通知请求创建、稳定标识、撤销、重建和错过提醒筛选继续由共享通知调度服务负责。
- 共享服务不得直接依赖 `AppKit`。
- macOS 生命周期适配：应用激活、系统唤醒时执行 reconciliation。
- iOS 生命周期适配：SwiftUI `scenePhase` 进入 `.active` 时执行 reconciliation。
- 提醒在创建或修改时直接提交 `UNCalendarNotificationTrigger`，不依赖应用内 Timer 或前序任务完成。
- 完成任务、删除提醒或修改提醒时，按稳定标识撤销对应系统待发送通知。
- 休眠、重启或长期未启动后，reconciliation 只补发最近错过的 1 条，其余过期提醒标记为已处理，避免集中弹出。
- 通知权限未授权时不伪造已调度状态；应用回到前台后重新检查并校准。

## 错误与平台差异

- 系统通知中心调用失败时保留业务提醒数据，后续生命周期校准可重试。
- iOS 不监听 `NSWorkspace`，macOS 专属代码通过平台条件编译或独立生命周期适配器隔离。
- iOS 前台通知展示沿用 `UNUserNotificationCenterDelegate` 的既有策略。

## 验证

- 单元测试覆盖今日推荐设置的默认开启、写入和隔离 UserDefaults suite。
- 静态检查两端设置入口和总览条件渲染。
- 通知测试覆盖独立里程碑提醒、稳定撤销、最近错过一条、重复 reconciliation 不重复投递。
- 执行 `git diff --check` 与相关 plist/localization 静态校验。
- 未经用户明确要求，不执行编译或测试命令。

## 非目标

- 不同步 macOS 与 iOS 的开关值。
- 不引入 CloudKit、App Group 跨平台偏好同步或 SwiftData schema 变更。
- 不改变今日推荐算法、排序、卡片内容或任务完成语义。
- 不提交代码或文档。

## 后续版本迁移

- 当前版本不删除数据库中未被 Project、Milestone 或 SubTask 关系引用的孤立 Reminder。
- 当前版本发布并稳定运行后，在新版本中单独设计数据迁移：先识别有效关系，再统一删除确认无引用的 Reminder。
- 该迁移必须使用独立的业务迁移版本，验证旧数据库升级、备份恢复和 Widget 共用主库场景后再发布。
