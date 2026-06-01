# Viabar Repository Instructions

本文件是 Viabar 仓库中面向编码代理的入口约束。开始任何修改前必须先阅读本文件。

## 1. 沟通与执行规则

1. 使用中文交流。
2. 用户未明确要求编译或运行测试时，不要通过编译或运行测试排查问题。
3. 默认优先使用源码阅读、静态搜索、`git diff --check`、`plutil -lint` 和只读数据库检查。
4. 不要擅自删除、覆盖或重建用户数据。涉及数据库文件删除、迁移、修复或重置时，必须先说明影响并获得用户确认。
5. 修改应保持最小范围。优先沿用现有模型、服务和交互，不要创建平行实现。

## 2. 真相源优先级

遇到文档与源码不一致时，按以下优先级判断：

1. 当前源码与用户本轮明确要求。
2. 本文件中的工程边界和数据安全约束。
3. `Viabar/specification.md` 中的产品理念、核心算法和交互语义。
4. `CLAUDE.md` 中的 iOS 规划。

注意：

- `Viabar/specification.md` 是产品规格来源，但部分目录和早期命名已过时。实现前必须核对当前源码。
- `CLAUDE.md` 是未来 iOS 和 CloudKit 规划草案，不代表当前 macOS 工程已经启用 CloudKit。
- 不要因为历史 spec 或 plan 中出现某个文件、路径或能力，就假设当前源码仍采用该实现。

## 3. 产品与技术边界

Viabar 是 Apple 生态下的轻量化项目里程碑工具。核心理念是降噪、聚焦和保持推进惯性。

强制技术边界：

- Swift 5.10+
- SwiftUI
- SwiftData
- Apple 原生框架优先
- macOS 14.0+
- 未来 iOS 17.0+
- WidgetKit 桌面组件
- macOS MenuBar Extra
- 不为已有能力引入第二套平行模型或服务
- 不引入非必要第三方业务依赖

当前 CloudKit 状态：

- 主库和回收站容器当前均显式使用 `cloudKitDatabase: .none`。
- iCloud / CloudKit 同步是规划方向，不是当前已启用能力。
- 启用 CloudKit 前必须单独设计并验证 schema、entitlements、双端模型兼容性和迁移策略。

## 4. 不可破坏的核心语义

### 4.1 两级任务树

任务结构固定为：

```text
Project -> Milestone -> SubTask
```

不要擅自增加第三层任务层级。

### 4.2 Rollup 进度

项目进度由系统计算，禁止手动存储或编辑。

- 项目包含 `N` 个里程碑，每个里程碑权重为 `1 / N`。
- 无子任务的里程碑：完成为 `1.0`，未完成为 `0`。
- 有 `M` 个子任务的里程碑：得分为 `已完成子任务数 / M`。
- 项目进度为所有里程碑加权得分之和。
- 结果按现有实现保留到 4 位小数。

### 4.3 提醒上下文穿透

项目级提醒触发时，文案不能只显示项目名称。必须定位该项目中最顶端的未完成里程碑；如其包含子任务，则继续定位第一个未完成子任务。

### 4.4 全局搜索

全局搜索必须覆盖：

- 项目名称
- 里程碑名称
- 子任务名称
- 备忘录内容

点击结果后应跳转到对应项目，并沿用现有搜索高亮链路定位目标。

## 5. 当前持久化架构

### 5.1 App Group 是唯一运行时数据源

App Group：

```text
group.com.tyrival.Viabar
```

主业务数据库：

```text
ViabarSharedStore/default.store
```

回收站数据库：

```text
ViabarSharedStore/trash.store
```

约束：

1. 主 App、Widget 和后续扩展必须读取同一个 App Group 主库。
2. 回收站独立使用 `trash.store`，不要将 `TrashItem` 重新混入主库 schema。
3. 禁止在共享库打开失败时回退到旧沙箱数据库。
4. 旧沙箱数据库只允许在一次性迁移中读取。迁移发布成功后清理旧文件及 SQLite `-wal`、`-shm`。
5. 清理旧文件失败不能阻止已可用的共享库启动；下次启动继续尝试清理。
6. 不要将 shell 环境下的 `~/Library/Application Support/default.store` 直接视为 Viabar 数据库。沙箱 App 的 Application Support 路径需要结合运行时容器判断，避免误删其他应用数据。

关键实现入口：

- `Viabar/System/SharedModelContainer.swift`
- `Viabar/System/TrashModelContainer.swift`
- `Viabar/ViabarApp.swift`
- `ViabarWidget/ViabarLargeWidget.swift`
- `ViabarWidget/WidgetProjectIntent.swift`
- `ViabarWidget/ToggleWidgetTaskIntent.swift`

### 5.2 当前共享库 schema

主库 schema 由 `SharedModelContainer.schema` 统一管理：

- `Project`
- `Milestone`
- `SubTask`
- `Memo`
- `Reminder`
- `NotificationScheduleEntry`
- `ArchiveFolder`
- `ProjectTemplate`
- `TemplateMilestone`
- `TemplateSubTask`
- `AppSettings`

回收站独立 schema：

- `TrashItem`

新增、删除或修改任何实体、字段、关系时，必须同时检查主 App、Widget、备份恢复和未来 iOS 兼容性。

## 6. SwiftData 数据结构变更红线

任何以下操作都属于数据库结构变更：

- 新增、删除或重命名 `@Model`
- 新增、删除、重命名或修改持久化字段
- 修改字段类型、可选性或默认值
- 修改 `@Attribute` 约束
- 修改 `@Relationship`、inverse 或 delete rule
- 将实体移入或移出某个 `Schema`

执行数据库结构变更前必须：

1. 明确指出这是 schema 变更，而不是普通 UI 改动。
2. 列出受影响的实体、字段、数据库文件、主 App、Widget、备份和恢复流程。
3. 检查旧数据库升级路径，禁止只验证新建空库。
4. 检查 App 与 Widget 是否仍使用相同主库 schema。
5. 检查是否需要业务数据格式化、默认值回填或派生数据重建。
6. 检查备份文件的兼容解码与恢复逻辑。
7. 在用户确认方案前，不直接提交结构性修改。

迁移框架落地前：

- 禁止直接向共享主库或 `trash.store` 增加持久化字段后结束任务。
- 对仅限本机、无需跨端查询的简单偏好设置，优先评估 `UserDefaults`，避免无必要地扩展 SwiftData schema。

迁移框架落地后：

- 使用 `VersionedSchema + SchemaMigrationPlan` 处理容器打开前的 SwiftData 结构迁移。
- 使用独立的 `dataMigrationVersion` 处理容器打开后的业务数据迁移。
- 每次需要业务格式化时递增版本，并按顺序实现 `update2()`、`update3()` 等步骤。
- 跨版本升级必须依次执行所有中间迁移。
- 主库与 `trash.store` 分别维护 schema 版本和业务迁移版本。

## 7. 备份与恢复约束

关键实现入口：

- `Viabar/Models/BackupSnapshot.swift`
- `Viabar/Services/BackupService.swift`

强制规则：

1. 备份必须覆盖项目、归档目录、模板、提醒、设置和回收站。
2. 恢复旧备份前必须先完整解码和校验，失败时不得先删除当前数据。
3. 新增备份字段时必须考虑旧备份兼容。
4. Swift `Codable` 属性默认值不等于旧 JSON 缺键兼容。缺键兼容应显式使用可选字段、`decodeIfPresent` 或自定义 `init(from:)`。
5. 必要时提升备份格式版本。
6. 迁移框架落地后，备份文件应记录 `schemaVersion` 和 `dataMigrationVersion`。
7. 恢复旧版本备份时，先转换为当前 Snapshot，再写入数据库，随后补跑业务迁移、回收站过期清理和派生数据重建。
8. 授权目录书签属于当前 Mac 的本地能力，不要从备份覆盖恢复。

## 8. 设置存储判断

当前设置有两类：

1. `AppSettings`：位于主 SwiftData 库，适用于需要跟随主业务数据管理的设置。
2. `UserDefaults` store：适用于本机简单偏好或为了避免不必要 schema 迁移而独立存储的值。

当前使用 `UserDefaults` 的设置：

- `WeekStartDaySettingsStore`
- `TrashRetentionSettingsStore`

新增设置前先判断：

- 是否需要跨设备同步？
- 是否需要出现在备份中？
- 是否需要被 Widget 或未来 iOS 读取？
- 是否值得为它引入 SwiftData schema 迁移？

不要默认把所有设置写入 `AppSettings`。

## 9. 国际化与交互复用

1. 用户可在 App 内切换系统语言、英文和简体中文。
2. 新增用户可见文案时同步更新：
   - `Viabar/en.lproj/Localizable.strings`
   - `Viabar/zh-Hans.lproj/Localizable.strings`
3. 弹窗、sheet、popover、MenuBar Extra 等独立 presentation root 也要检查 locale 注入。
4. 搜索跳转高亮优先复用现有 `SearchTargetHighlight` 链路。
5. 新增右侧面板优先复用已有 drawer 风格，不要另造视觉壳层。
6. macOS 交互优先使用原生 SwiftUI / AppKit 能力，并遵循现有 UI 密度。

## 10. 数据库改动检查清单

涉及 SwiftData、备份、Widget 或 App Group 时，至少执行以下静态检查：

```bash
rg -n "@Model|Schema\\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "legacyStoreURL|applicationSupportDirectory|default\\.store|trash\\.store|ViabarSharedStore|cloudKitDatabase" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "BackupSnapshot|BackupSettingsSnapshot|decodeIfPresent|init\\(from decoder" Viabar ViabarTests --glob '*.swift'
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

数据库文件排查默认只读：

```bash
sqlite3 -readonly "<store-path>" "PRAGMA integrity_check;"
sqlite3 -readonly "<store-path>" ".tables"
sqlite3 -readonly "<store-path>" "PRAGMA table_info(<table-name>);"
```

删除实际数据库文件前必须：

1. 确认文件属于 Viabar。
2. 确认目标不是当前唯一有效数据源。
3. 确认文件未被进程占用。
4. 获得用户明确授权。

## 11. 常见失败模式

看到以下错误时，不要先做 UI 层补丁：

```text
no such table: Z...
no such column: t0.Z...
Could not create ModelContainer
```

优先检查：

1. App 与 Widget 是否打开同一个 App Group 主库。
2. 当前源码 schema 与磁盘 SQLite 表结构是否一致。
3. 是否直接修改了 `@Model` 但没有迁移计划。
4. 是否错误地将新实体混入已有主库。
5. 是否存在旧库 fallback 或多个运行时数据源。
6. 备份 JSON 是否缺少兼容解码。

不要通过创建默认数据、吞掉 fetch 错误或回退旧库掩盖结构异常。

