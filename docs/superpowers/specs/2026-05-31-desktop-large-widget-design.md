# Desktop Large Widget Design

日期：2026-05-31

## 目标

为 Viabar 增加一个 macOS 桌面小组件。首个版本只支持 Large 尺寸，并允许用户通过系统右键菜单进入“编辑小组件”，从当前活跃项目中选择一个项目。

小组件展示所选项目的图标、名称、进度和未完成任务。用户可以直接点击任务前方的复选框完成任务；完成后列表立即刷新，后续任务自动补位。

本轮开发同时将现有 SwiftData 数据库迁移到 App Group 共享容器，使主程序与 Widget Extension 访问同一份本地数据。此次不启用 iCloud，但共享容器设计不得阻碍后续接入 CloudKit。

## 已确认的产品决策

- 仅支持 Large Widget。
- Widget 必须使用系统提供的右键“编辑小组件”入口，不自行模拟配置菜单。
- 首次添加后不自动选择项目；显示空状态和右键编辑提示。
- 项目选择器只显示 `isArchived == false` 的活跃项目。
- 顶部左侧显示所选项目的 SF Symbol 与项目名称，右侧显示短进度条与百分比。
- 图标和项目名称使用与任务正文接近的紧凑尺寸，项目名称使用粗体。
- 任务列表按项目内现有顺序平铺所有未完成任务与子任务。
- 一级任务和子任务分别占一行；子任务缩进显示，不显示父任务名称。
- 一级任务和子任务前方均提供可点击复选框。
- 任务有提醒时才显示第二行小字；没有提醒时不占用第二行空间。
- 已过期提醒显示红色；今天尚未过期的提醒显示橙色；未来日期提醒显示灰色。
- 列表无法容纳全部未完成项时，按顺序截断，并在底部显示“还有 N 项未完成”。
- 勾选后立即刷新列表，完成项消失，后续内容自动补位。
- Widget 内的完成语义与主程序一致：完成带子任务的一级任务会同时完成全部子任务；同级子任务全部完成后，父任务自动完成。
- 新增 Widget 文案必须支持 `zh-Hans` 与 `en` 国际化。
- 已有数据必须自动迁移到 App Group，不允许要求用户重新创建项目。
- 本轮不启用 iCloud 同步，只为后续 CloudKit 接入保留兼容结构。
- 本轮实施与排查遵守仓库规则：未另行授权时不通过编译代码排查问题。

## 系统能力与社区调查

### 系统配置入口

macOS 的可配置 Widget 使用 WidgetKit 的 `AppIntentConfiguration` 和 App Intents 的 `WidgetConfigurationIntent`。配置参数由系统编辑界面呈现；桌面 Widget 的右键菜单入口由 macOS 提供，不应由应用自行增加。

因此：

- 使用 `StaticConfiguration` 无法满足项目选择需求；
- 使用 `AppIntentConfiguration` 配合项目参数，才能让系统生成“编辑小组件”界面；
- 项目候选列表应通过动态 App Entity 查询返回。

参考：

- [AppIntentConfiguration](https://developer.apple.com/documentation/widgetkit/appintentconfiguration)
- [WidgetConfigurationIntent](https://developer.apple.com/documentation/appintents/widgetconfigurationintent)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

### 右键编辑异常

社区中存在 macOS Widget 配置或加载异常反馈，包括 Intent 配置在 Mac 上无法正常工作的历史案例：

- [WidgetKit on Mac with Intent doesn't work](https://stackoverflow.com/questions/64598227/widgetkit-on-mac-with-intent-doesnt-work)

截至本设计日期，未找到足够证据表明近期 macOS 存在稳定复现的系统级问题，会统一移除正确配置 Widget 的“编辑小组件”入口。上次尝试中缺少入口，优先按以下方向排查：

1. 是否误用了 `StaticConfiguration`；
2. `WidgetConfigurationIntent` 是否正确声明并加入 Widget Extension；
3. App Entity 查询是否可被扩展加载；
4. 安装新版本后，系统 Widget 缓存是否仍引用旧扩展；
5. 实际桌面右键菜单在当前 macOS 版本上是否可见。

最后一项必须在明确授权编译和安装后进行桌面实测。

## 实现方案

采用原生交互式 Widget 与 App Group 共享 SwiftData：

- 新增 `ViabarWidgetExtension`；
- Widget 使用 `AppIntentConfiguration`；
- 新增项目选择 Intent 与动态项目实体查询；
- 主程序与 Widget Extension 使用同一 App Group 中的 SwiftData 数据库；
- Widget 的任务完成按钮通过交互式 `AppIntent` 写回共享数据库；
- 完成操作后调用 `WidgetCenter` 刷新时间线；
- 主程序升级后自动迁移旧数据库到 App Group；
- 本轮共享容器明确不启用 CloudKit。

不采用 JSON 快照桥接。该方案会引入第二份可变状态，任务完成写回和刷新一致性更复杂，也会增加未来 iCloud 同步的维护负担。

不采用只读 Widget。点击任务后打开主程序无法满足桌面直接完成任务的目标。

## 数据共享与未来 iCloud

### 共享容器

主程序当前使用默认 SwiftData 存储位置。Widget Extension 是独立进程，不能直接依赖主程序默认容器。新增共享容器工厂，由主程序和 Widget 共同使用：

- `groupContainer` 指向 Viabar 专用 App Group；
- `cloudKitDatabase` 在本轮明确使用 `.none`；
- Schema 保持与主程序一致，避免 Widget 写入产生不兼容存储。

Apple 的 `ModelConfiguration` 同时提供 `groupContainer` 与 `cloudKitDatabase` 参数，因此本地 App Group 共享容器不会阻碍未来使用 CloudKit 私有数据库进行跨设备同步。

参考：

- [ModelConfiguration initializer](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:isstoredinmemoryonly:allowssave:groupcontainer:cloudkitdatabase:))
- [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)

### Entitlement

主程序和 Widget Extension 都必须声明同一个 App Group entitlement。此次不新增 iCloud 或 CloudKit entitlement。

### 旧数据库自动迁移

迁移必须在主程序创建正式共享容器前完成：

1. 检查共享数据库是否已经存在；
2. 若共享数据库已存在，直接使用共享容器；
3. 若共享数据库不存在但旧数据库存在，将旧数据库相关文件复制到 App Group 中的临时位置；
4. 校验临时副本可以被预期 Schema 打开；
5. 将已校验副本切换为正式共享数据库；
6. 记录迁移完成标记；
7. 保留旧数据库，不在首次迁移后立即删除。

如果迁移失败：

- 主程序继续使用旧数据库；
- 不创建空白共享数据库覆盖现有数据；
- 记录可诊断错误；
- Widget 显示暂时无法读取数据的空状态。

## Widget 配置

### 项目实体

新增可供 Widget 配置使用的项目实体：

- 标识使用 `Project.projectId`；
- 标题使用 `Project.title`；
- 查询结果只包含 `isArchived == false` 的项目；
- 排序沿用活跃项目的 `orderIndex`，必要时使用标题作为稳定次级排序。

### 项目选择 Intent

新增 `SelectWidgetProjectIntent: WidgetConfigurationIntent`：

- 项目参数允许为空；
- 首次添加 Widget 时不自动选择任何项目；
- 系统编辑界面使用动态项目实体查询生成候选列表。

Widget 使用 `AppIntentConfiguration`，只声明 `.systemLarge`。

### 配置失效

若用户选择的项目后续被归档或删除：

- Widget 不自动切换到其他项目；
- Widget 显示“项目不可用，请重新选择项目”；
- 文案提示用户通过右键“编辑小组件”重新配置。

## 任务列表

### 条目模型

Widget 使用轻量快照，不把 SwiftData 模型对象直接暴露给 View。每个条目至少包含：

- 条目类型：一级任务或子任务；
- 对应 UUID；
- 标题；
- 是否为子任务；
- 提醒展示日期；
- 提醒颜色分类。

### 平铺规则

按以下顺序生成未完成条目：

1. 按 `Milestone.orderIndex` 排序一级任务；
2. 一级任务尚未完成时，先加入一级任务条目；
3. 按 `SubTask.orderIndex` 排序该任务的子任务；
4. 将每个尚未完成的子任务加入列表；
5. 子任务以缩进区分层级，不显示父任务标题。

列表仅展示未完成条目。完成项不进入快照。

### 截断规则

Large Widget 使用固定的最大可见任务行预算。预算需要考虑有提醒条目会额外占用一行小字：

- 按生成顺序逐项放入；
- 下一项无法完整容纳时停止；
- 若仍有未展示条目，在底部显示“还有 N 项未完成”；
- 不通过持续缩小字号挤入更多条目。

## 提醒展示

### 展示范围

一级任务和子任务分别读取自身 `Reminder`。项目级提醒不在 Widget 中额外生成条目，因为它不对应独立任务；项目级提醒继续保留在菜单栏现有逻辑中。

### 颜色分类

提醒使用现有 `Reminder.displayFireDate` 作为展示日期，并按当前时间分类：

- `fireDate < now`：已过期，红色；
- `fireDate >= now` 且与 `now` 位于同一自然日：今天尚未过期，橙色；
- `fireDate` 晚于今天：未来提醒，灰色。

日期文本沿用现有日期格式设置。重复提醒沿用现有 `Reminder.displayFireDate` 和循环推进语义。

## Widget 外观

### 顶部区域

顶部使用紧凑单行布局：

- 左侧为项目 SF Symbol；
- 图标后显示项目名称；
- 项目名称使用任务正文大小附近的粗体；
- 右侧使用短进度条和百分比；
- 进度值读取现有 `Project.progress` Rollup 算法；
- 色彩优先沿用项目 `accentColor`，并保证桌面背景上的可读性。

### 任务区域

- 每个条目前方显示可点击复选框；
- 一级任务正文正常对齐；
- 子任务正文缩进；
- 标题允许合理截断；
- 仅在任务有提醒时显示第二行小字；
- 不显示父任务副标题；
- 底部在必要时显示剩余未完成数量。

### 空状态

Widget 至少提供以下国际化空状态：

- 尚未选择项目：“请选择项目”；“右键小组件 > 编辑小组件”；
- 项目失效：“项目不可用，请重新选择项目”；
- 数据读取失败：“暂时无法读取数据”；
- 项目已完成：“当前没有未完成任务”。

## 交互式完成

新增任务完成 App Intent：

- 输入任务类型与 UUID；
- 打开共享 SwiftData 容器；
- 查找对应 `Milestone` 或 `SubTask`；
- 沿用主程序现有联动语义；
- 保存共享模型上下文；
- 调用 `WidgetCenter.shared.reloadTimelines(...)` 刷新 Widget。

联动规则：

- 完成没有子任务的一级任务：切换一级任务完成状态；
- 完成带子任务的一级任务：同时切换全部子任务状态；
- 完成子任务：切换子任务状态，并调用父任务的完成状态同步；
- 全部子任务完成后，父任务自动完成。

Widget 写操作不得另建一套与 `ProjectService` 不一致的规则。若扩展不能直接复用主程序服务，应将纯业务状态变更提取为主程序与 Widget 均可调用的共享逻辑。

若写入失败：

- 不伪造成功状态；
- 保留当前时间线快照；
- 等待下一次刷新；
- 记录可诊断错误。

## 国际化

Widget 新增文案加入：

- `Viabar/zh-Hans.lproj/Localizable.strings`
- `Viabar/en.lproj/Localizable.strings`
- Widget Extension 对应的本地化资源

至少覆盖：

- Widget 名称与描述；
- 项目选择参数标题；
- “请选择项目”；
- “右键小组件 > 编辑小组件”；
- “项目不可用，请重新选择项目”；
- “暂时无法读取数据”；
- “当前没有未完成任务”；
- “还有 %lld 项未完成”。

## 验证范围

### 静态检查

- Widget Extension target 已加入工程；
- 主程序与 Widget Extension 使用相同 App Group entitlement；
- Widget 使用 `AppIntentConfiguration` 而非 `StaticConfiguration`；
- `SelectWidgetProjectIntent` 支持动态活跃项目候选；
- Widget 只声明 `.systemLarge`；
- 国际化资源完整；
- `git diff --check` 通过。

### 单元测试

- 活跃项目查询排除归档项目；
- 未完成任务与子任务按顺序平铺；
- 子任务带缩进标识但不附带父任务副标题；
- 完成项不进入 Widget 快照；
- 提醒颜色分类覆盖已过期、今天尚未过期和未来提醒；
- 提醒条目影响可见行预算；
- 截断后剩余数量正确；
- 完成一级任务时联动全部子任务；
- 完成最后一个未完成子任务时父任务自动完成；
- 旧数据库迁移成功；
- 迁移失败时保留旧数据库并回退。

### 授权编译后的手工验证

只有用户明确要求编译和安装后，才执行以下实测：

1. 添加 Large Widget 到桌面；
2. 右键确认出现系统“编辑小组件”入口；
3. 进入编辑界面并选择活跃项目；
4. 验证未选择项目、项目失效、项目完成和读取失败空状态；
5. 点击一级任务和子任务复选框，确认任务立即消失并自动补位；
6. 验证提醒颜色；
7. 归档已选项目后确认 Widget 提示重新选择；
8. 验证迁移前已有的项目、设置、提醒、模板和归档仍然完整。

## 非目标

本轮不实现：

- Small 或 Medium Widget；
- iCloud / CloudKit 正式同步；
- 项目级提醒的独立 Widget 条目；
- Widget 内新增任务；
- Widget 内编辑提醒；
- 已归档项目选择；
- 自定义右键菜单；
- Widget 内打开主程序后的深链跳转优化。
