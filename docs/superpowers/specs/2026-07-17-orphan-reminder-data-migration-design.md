# 孤立 Reminder 数据迁移设计

## 目标

1. 新版本首次打开主业务库时，一次性删除未被任何 Project、Milestone 或 SubTask 引用的孤立 Reminder。
2. 修复项目、里程碑和子任务的提醒替换与清空流程，避免继续产生孤立 Reminder。
3. 备份恢复完成后执行同样的孤立数据清理。

## 数据结构边界

- 本次是容器打开后的业务数据迁移，不修改任何 `@Model`、字段、关系、Schema 或数据库文件路径。
- 主业务数据库仍为 App Group 中的 `ViabarSharedStore/default.store`。
- 回收站 `trash.store` 保存 Reminder 的值快照，不引用主库 Reminder 实体，因此不参与引用集合。
- macOS、iOS 和 Widget 继续使用现有共享 schema。

## 迁移执行器

新增 `MainStoreDataMigrator`，包含：

- 当前业务迁移版本 `currentVersion = 1`。
- `UserDefaults` key：`mainStoreDataMigrationVersion`。
- `runPendingMigrations(in:defaults:)`：读取已完成版本，按顺序执行缺失迁移。
- `removeOrphanReminders(in:)`：可被首次迁移和备份恢复复用的清理操作。

macOS 与 iOS 主 App 在主 ModelContainer 创建成功后、注册业务服务前运行 pending migrations。Widget 不主动执行迁移。

迁移成功保存后才写入版本号。迁移失败时记录错误、保持旧版本号并允许 App 继续启动；下次启动重新尝试。

## 孤立判断

清理时分别 fetch 全部 Project、Milestone 和 SubTask，收集三个实体当前关系中非空 Reminder 的 SwiftData `persistentModelID`。

随后 fetch 全部 Reminder：

- `persistentModelID` 出现在引用集合中：保留。
- `persistentModelID` 不在引用集合中：删除。

判断覆盖已完成、归档或暂时脱离项目树但仍存在于主库的 owner，避免仅遍历“活跃项目”造成误删。

## 防止新增孤立数据

ProjectService 为 Project、Milestone、SubTask 提供统一的提醒更新入口。

每次替换按以下顺序执行：

1. 保存 owner 当前旧 Reminder 引用。
2. 将新 Reminder 赋给 owner。
3. 若旧 Reminder 存在且不是传入的同一个实体实例，则从 ModelContext 删除旧 Reminder。
4. 保存主库并同步对应系统通知请求。

传入同一个 Reminder 实体时不删除，兼容原地更新；即使两个不同实体意外拥有相同业务 UUID，也仍会删除被替换的旧实体。传入 nil 时删除旧 Reminder 并撤销对应通知。

macOS 和 iOS 的项目编辑、里程碑提醒、子任务提醒入口都必须调用 ProjectService，不再直接替换关系后只调用 `save()`。

## 备份恢复

备份恢复仍先完成完整解码、删除可恢复业务数据、重建项目树并保存。保存成功后调用 `removeOrphanReminders(in:)`，再重建通知时间线。

清理失败时恢复操作返回错误，不把一次不完整的恢复报告为成功。迁移版本不因备份恢复清理而改变。

## 测试

- 无引用 Reminder 会被删除。
- Project、Milestone、SubTask 引用的 Reminder 均被保留。
- 迁移成功写入版本 1，重复运行不重复执行。
- 替换三个 owner 的 Reminder 后旧对象从 ModelContext 消失，新对象保留。
- 清空三个 owner 的 Reminder 后旧对象删除。
- 传入同一 Reminder 不会误删。
- 备份恢复后不存在孤立 Reminder。

## 验证与执行约束

- 执行 `git diff --check`。
- 执行 `plutil -lint Viabar.xcodeproj/project.pbxproj`。
- 静态搜索 schema、备份和 target membership，确认无结构变更且迁移器同时进入 macOS/iOS 主 App 编译路径。
- 未经用户明确要求，不编译、不运行测试、不提交。

## 非目标

- 不清理仍被任何 owner 引用的 Reminder，即使 owner 已完成或归档。
- 不修改 `trash.store`。
- 不修改备份格式版本。
- 不引入 VersionedSchema 或 SchemaMigrationPlan。
