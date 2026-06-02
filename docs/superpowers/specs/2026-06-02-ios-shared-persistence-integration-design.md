# iOS Shared Persistence Integration Design

## 目标

将已经确认交互的 iOS 静态原型接入真实 SwiftData 本地数据库，并保证 macOS App、macOS Widget、iOS App 和 iOS Widget 沿用同一份 schema 契约。

本阶段完成后：

1. iOS App 使用现有业务模型展示和修改真实数据。
2. iOS App 与 iOS Widget 打开同一个本机 App Group 主库。
3. 四个 Target 统一使用 App Group 标识 `group.com.tyrival.Viabar`。
4. Widget 继续通过 `SharedModelContainer.makeWidgetContainer()` 打开主库，不创建平行数据源。
5. 回收站服务在 iOS 启动时完成注册，但回收站 UI 留到下一阶段。
6. CloudKit 继续保持关闭。

## 已确认边界

### 本地数据库与跨设备同步

四个 Target 统一使用：

```text
group.com.tyrival.Viabar
```

主业务数据库继续使用：

```text
ViabarSharedStore/default.store
```

回收站数据库继续使用：

```text
ViabarSharedStore/trash.store
```

App Group 只负责同一设备上的 App 与 Widget 共享。即使四个 Target 使用相同标识，当前阶段也不声称 Mac 与 iPhone 已经跨设备同步。

跨设备同步必须等待 Apple Developer Program 恢复后，通过单独设计的 CloudKit Container、entitlements、schema 兼容和迁移策略实现。

### 不迁移旧 iOS 原型库

旧 iOS 本地 App Group：

```text
group.com.tyrival.ViabariOS
```

本阶段不删除、不覆盖、不移动该目录中的任何文件。切换 App Group 后，iOS App 使用新约定打开主库。旧目录保留，避免误伤用户数据。

### 不修改 SwiftData Schema

本阶段不得新增、删除或修改：

- `@Model`
- 持久化字段
- 字段类型、可选性或默认值
- `@Attribute`
- `@Relationship`
- inverse
- delete rule
- `SharedModelContainer.schema` 中的实体列表

主 App 和 Widget 必须继续复用 `SharedModelContainer.schema`：

```text
Project
Milestone
SubTask
Memo
Reminder
NotificationScheduleEntry
ArchiveFolder
ProjectTemplate
TemplateMilestone
TemplateSubTask
AppSettings
```

回收站继续使用独立 schema：

```text
TrashItem
```

## 共享容器

### App Group 标识

`SharedModelContainer.appGroupIdentifier` 改为单一常量：

```swift
static let appGroupIdentifier = "group.com.tyrival.Viabar"
```

移除 iOS 与 macOS 的条件分支。

### 主库入口

保留现有三个入口：

```swift
SharedModelContainer.makeMainAppContainer()
SharedModelContainer.makeIOSAppContainer()
SharedModelContainer.makeWidgetContainer()
```

职责保持清晰：

- macOS App 使用 `makeMainAppContainer()`，保留旧沙箱主库的一次性迁移逻辑。
- iOS App 使用 `makeIOSAppContainer()`，直接打开 App Group 主库，不新增旧 iOS App Group 迁移。
- macOS Widget 和 iOS Widget 使用 `makeWidgetContainer()`，只读取已经存在的 App Group 主库。

禁止在共享库打开失败时回退旧沙箱数据库。

### 回收站入口

iOS App 启动时同时创建：

```swift
SharedModelContainer.makeTrashContainer()
```

它继续打开同一 App Group 下的独立 `trash.store`。不得把 `TrashItem` 混入主库 schema。

## iOS 服务注册

### 复用现有服务

iOS App 不创建第二套业务模型或持久化服务。启动时注册现有服务：

- `ServiceContainer`
- `ProjectService`
- `NotificationScheduleService`
- `TrashService`

`ProjectService` 继续作为项目、任务、子任务、备忘录、收藏、归档文件夹和完成状态的唯一写入口。

### Widget 刷新

`ProjectService.save()` 已经负责刷新：

```swift
SharedModelContainer.widgetKinds
```

iOS 页面通过 `ProjectService` 完成写操作后，iOS Widget 继续沿用该刷新入口。

Widget 自身继续使用：

```swift
SharedModelContainer.makeWidgetContainer()
```

不得为 iOS Widget 增加单独数据库、单独 schema 或平行查询模型。

## iOS 页面数据流

### 总览

总览页使用真实 `Project` 查询：

```swift
@Query(sort: \Project.orderIndex)
```

页面仅展示未归档项目，并按 `isFavorite` 分为：

- 星标项目
- 其他项目

卡片继续展示：

- 项目色竖线
- 项目图标
- 项目名称
- 收藏星标
- 最顶端未完成任务
- 第一个未完成子任务
- 提醒状态色
- 进度百分比和进度环

### 项目详情

项目详情直接使用真实 `Project`、`Milestone`、`SubTask` 和 `Memo`。

保留当前已确认交互：

- 单击任务、子任务或备忘录后，在底部输入框编辑。
- 底部纸飞机提交。
- 长按菜单支持编辑、复制和删除。
- 长按任务支持新增子任务。
- 完成状态切换使用现有 `ProjectService`。
- 收藏和归档使用现有 `ProjectService`。

### 搜索

iOS 全局搜索必须覆盖：

- 项目名称
- 里程碑名称
- 子任务名称
- 备忘录内容

搜索结果保留目标实体 ID，并继续支持：

- 跳转项目详情
- 自动切换任务或备忘录 Tab
- 滚动定位
- 只播放一次的橙色高亮
- 归档项目路径前缀
- 归档树祖先展开

优先复用现有 macOS `GlobalSearchIndex` 的索引语义，不在 iOS 新建第二套搜索规则。

### 归档

归档页直接使用真实 `ArchiveFolder` 和已归档 `Project`。

保留已确认交互：

- 多级树结构
- 展开时才渲染子节点
- 新建根文件夹
- 长按文件夹新增子文件夹
- 重命名文件夹
- 删除空文件夹
- 删除非空文件夹前二次提示
- 归档项目取消归档
- 归档项目删除前二级确认

删除项目、任务、子任务和备忘录时，不得绕过现有回收站语义。

## 回收站规划

本阶段只完成 iOS 端 `trash.store` 和 `TrashService` 注册。总览右上角回收站按钮继续保留占位入口。

下一阶段单独实现：

- 回收站列表
- 项目、任务、子任务和备忘录分类展示
- 恢复
- 彻底删除
- 清空回收站
- 保留周期设置

## Entitlements

以下四个 Target 都必须声明：

```text
group.com.tyrival.Viabar
```

对应文件：

```text
Viabar/Viabar.entitlements
ViabarWidget/ViabarWidget.entitlements
ViabariOS/ViabariOS.entitlements
ViabariOSWidget/ViabariOSWidget.entitlements
```

本阶段不得新增 iCloud 或 CloudKit entitlement。

## CloudKit 预留

主库和回收站继续显式使用：

```swift
cloudKitDatabase: .none
```

启用 CloudKit 前必须单独确认：

1. CloudKit Container 标识。
2. 四端 entitlements。
3. `VersionedSchema + SchemaMigrationPlan`。
4. macOS 已有主库升级路径。
5. iOS 本地主库升级路径。
6. 旧 `group.com.tyrival.ViabariOS` 数据是否需要迁移。
7. `trash.store` 是否参与云同步。
8. `AppSettings` 中本地设置与同步设置的拆分。
9. 备份格式兼容。
10. 远程变更后的 Widget 刷新策略。

## 实施顺序

1. 将 iOS App 和 iOS Widget entitlements 改为 `group.com.tyrival.Viabar`。
2. 移除 `SharedModelContainer.appGroupIdentifier` 的平台分支。
3. 为 iOS App 注册真实主库、回收站容器和现有业务服务。
4. 增加 iOS 持久化页面适配层，直接使用现有模型和服务。
5. 将总览和项目详情切换到真实数据。
6. 将搜索和归档切换到真实数据。
7. 保持 Widget 使用现有共享容器和刷新入口。
8. 执行静态检查，由用户在 Xcode 中编译、运行和手测。

## 静态验证

实现后至少执行：

```bash
rg -n "@Model|Schema\\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift'
rg -n "legacyStoreURL|applicationSupportDirectory|default\\.store|trash\\.store|ViabarSharedStore|cloudKitDatabase" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift'
rg -n "group\\.com\\.tyrival\\.Viabar|group\\.com\\.tyrival\\.ViabariOS" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift' --glob '*.entitlements'
rg -n "BackupSnapshot|BackupSettingsSnapshot|decodeIfPresent|init\\(from decoder" Viabar ViabarTests --glob '*.swift'
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
plutil -lint Viabar/Viabar.entitlements ViabarWidget/ViabarWidget.entitlements
plutil -lint ViabariOS/ViabariOS.entitlements ViabariOSWidget/ViabariOSWidget.entitlements
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

负向 `rg` 无命中属于成功条件。

## 用户手测

由用户在 Xcode 中完成编译与运行验证：

1. 运行 iOS App，确认真实项目可以显示。
2. 新增或编辑任务、子任务和备忘录，确认退出并重新进入 App 后数据仍存在。
3. 切换收藏状态，确认总览分组和星标同步变化。
4. 归档项目，确认归档树可以展开并显示项目。
5. 使用全局搜索跳转任务、子任务和备忘录，确认定位和一次性高亮正常。
6. 添加 iOS Medium 和 Large Widget，确认可以选择项目。
7. 在 iOS App 中切换任务完成状态，确认 Widget 刷新。
8. 在 Widget 中切换任务完成状态，确认 iOS App 重新显示后状态一致。
9. 运行 macOS App 和 macOS Widget，确认现有本地数据与行为不受影响。

## 非目标

- 不启用 iCloud 或 CloudKit。
- 不修改 SwiftData schema。
- 不删除、覆盖、移动或重建任何数据库。
- 不迁移旧 `group.com.tyrival.ViabariOS` 数据。
- 不实现 iOS 回收站页面。
- 不实现 iOS 设置页、报告页、备份或恢复。
- 不重构 macOS 主界面。
- 不引入第三方依赖。
