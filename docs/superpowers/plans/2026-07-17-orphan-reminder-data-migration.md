# 孤立 Reminder 数据迁移实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一次性清理主库孤立 Reminder，并修复所有提醒替换入口以防止再次产生。

**Architecture:** 新增容器打开后的 `MainStoreDataMigrator`，用本地 UserDefaults 记录业务迁移版本，按三个 owner 实体的真实关系构造引用集合。ProjectService 统一负责提醒关系替换和旧实体删除，备份恢复复用无版本标记的清理函数。

**Tech Stack:** Swift 5.10+、SwiftData、UserDefaults、macOS 14+、iOS 17+

## Global Constraints

- 不修改 SwiftData schema、备份格式、主库路径或 trash.store。
- 只删除未被任何 Project、Milestone、SubTask 引用的 Reminder。
- 迁移失败不阻止启动，且不写成功版本；下次启动重试。
- 直接在 main 工作区修改，不提交。
- 未经用户明确要求，不编译、不运行测试。

---

### Task 1: 业务数据迁移器

**Files:**
- Create: `Viabar/System/MainStoreDataMigrator.swift`
- Modify: `Viabar.xcodeproj/project.pbxproj`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Produces: `MainStoreDataMigrator.currentVersion`
- Produces: `MainStoreDataMigrator.runPendingMigrations(in:defaults:) throws`
- Produces: `MainStoreDataMigrator.removeOrphanReminders(in:) throws -> Int`

- [x] 写入测试：三个 owner 引用保留、孤立 Reminder 删除、版本成功写入、重复运行跳过。
- [x] 实现版本 1 迁移，保存成功后写入 `mainStoreDataMigrationVersion`。
- [x] 把迁移器加入 iOS 主 App Sources；macOS 由同步目录自动包含。

### Task 2: 主 App 启动接入

**Files:**
- Modify: `Viabar/ViabarApp.swift`
- Modify: `ViabariOS/ViabariOSApp.swift`

**Interfaces:**
- Consumes: `MainStoreDataMigrator.runPendingMigrations(in:defaults:)`

- [x] 在两个主 ModelContainer 创建成功后、服务注册前执行 pending migration。
- [x] 捕获错误并输出迁移失败日志，保持 App 可启动。
- [x] Widget 不接入迁移器。

### Task 3: ProjectService 统一提醒替换

**Files:**
- Modify: `Viabar/Services/ProjectService.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Produces: `ProjectService.updateReminder(_:for: Project)`
- Preserves: milestone/subtask `updateReminder` signatures

- [x] 写入 Project、Milestone、SubTask 替换、清空和同对象更新测试。
- [x] 三个入口先赋新关系，再删除不同实体的旧 Reminder，然后保存和同步通知。

### Task 4: macOS 与 iOS 编辑入口收口

**Files:**
- Modify: `Viabar/Views/Component/NewProjectView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentProjectCreationView.swift`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift`

**Interfaces:**
- Consumes: ProjectService 三类 `updateReminder` overload

- [x] 项目编辑不再直接替换 `project.reminder`。
- [x] 任务行内 Reminder binding 不再直接赋值后仅 save。
- [x] 保留现有通知同步行为。

### Task 5: 备份恢复后清理

**Files:**
- Modify: `Viabar/Services/BackupService.swift`
- Test: `ViabarTests/ViabarTests.swift`

**Interfaces:**
- Consumes: `MainStoreDataMigrator.removeOrphanReminders(in:)`

- [x] 在恢复项目树首次保存成功后清理孤立 Reminder。
- [x] 清理完成后再重建通知时间线。
- [x] 保留恢复失败向调用方抛错的语义。

### Task 6: 静态验证

- [x] 运行 `git diff --check`。
- [x] 对工程文件和中英文 localization 运行 `plutil -lint`。
- [x] 静态确认没有新增或修改 `@Model`、字段、关系和 Schema。
- [x] 静态确认迁移器只进入 macOS/iOS 主 App，不进入 Widget。
- [x] 未运行编译或测试命令。
