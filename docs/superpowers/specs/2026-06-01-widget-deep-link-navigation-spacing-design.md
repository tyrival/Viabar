# Widget Deep Link Navigation And Spacing Design

日期：2026-06-01

## 目标

为现有 macOS Large Widget 增加打开主程序后的精准定位能力，并略微放宽任务列表行间距。

用户点击 Widget 中的项目区域时，主程序应打开对应项目；点击任务标题时，主程序应进一步定位到对应里程碑或子任务，并沿用全局搜索现有的橙色高亮反馈。

本轮不修改任务完成语义、不新增持久化字段、不调整 SwiftData schema。

## 已确认的产品决策

- 点击任务前方 checkbox：只执行现有后台完成操作，不打开主程序。
- 点击一级任务标题：打开主程序，选中对应项目，滚动到对应里程碑并橙色高亮约 5 秒。
- 点击子任务标题：打开主程序，选中对应项目，滚动到对应子任务并橙色高亮约 5 秒。
- 点击 Widget 顶部项目区域或未被其他交互占用的空白区域：打开主程序，选中对应项目并沿用现有项目高亮反馈。
- Widget 任务列表 `VStack` 行间距由 `7` 调整为 `9`。
- checkbox 的点击区域与打开主程序的标题点击区域必须彼此独立，避免勾选任务时意外启动主程序。
- 本轮不通过编译或运行测试排查问题；实现后执行静态检查。

## 系统能力

Apple 对交互式 Widget 的建议是：

- 直接执行功能的交互使用带 `AppIntent` 的 `Button` 或 `Toggle`；
- 用于打开主程序的交互使用 `Link` 或 `widgetURL(_:)`。

因此现有 checkbox 继续使用 `ToggleWidgetTaskIntent`，打开主程序的交互使用 URL deep link。

参考：

- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [widgetURL(_:)](https://developer.apple.com/documentation/swiftui/view/widgeturl(_:))

## URL 设计

主程序新增 Viabar 自有 URL scheme，并统一解析以下形式：

```text
viabar://navigate/project/<project-id>
viabar://navigate/milestone/<project-id>/<milestone-id>
viabar://navigate/subtask/<project-id>/<milestone-id>/<subtask-id>
```

约束：

- 所有 ID 均使用 UUID 字符串；
- 解析失败时忽略该 URL，不创建无效导航请求；
- URL 中找不到对应项目时保持当前界面，不创建默认数据；
- 本轮不为 memo 增加 Widget deep link，因为 Widget 当前不展示 memo。

## 复用现有导航链路

主程序收到 URL 后，将其转换为现有 `GlobalSearchNavigationRequest`：

- 项目 URL 转换为 `.project`；
- 一级任务 URL 转换为 `.milestone(milestoneID)`；
- 子任务 URL 转换为 `.subTask(milestoneID:subTaskID:)`。

转换后的请求交给现有 `AppRuntimeController.navigate(to:)`。该控制器负责显示主窗口；`ContentView` 继续负责消费请求、选中项目、滚动目标并触发现有高亮。

不得为 Widget 新建第二套 selection、scroll 或 highlight 状态。

## Widget 点击区域

Widget 内容区域使用单一项目级 `widgetURL(_:)` 作为默认打开行为：

```text
viabar://navigate/project/<project-id>
```

任务标题使用独立 `Link` 覆盖默认行为：

- 一级任务标题指向 milestone URL；
- 子任务标题指向 subtask URL。

checkbox 保持现有 `Button(intent:)`，优先执行后台完成操作。

这样既允许用户点击 Widget 空白区域进入项目，也能在点击具体标题时精准定位，不会牺牲 checkbox 的直接完成能力。

## 行间距

现有任务列表行间距为 `7`。本轮调整为 `9`：

- 仍保持紧凑桌面 Widget 风格；
- 提升相邻任务标题与 reminder 第二行之间的视觉分隔；
- 不调整字号、缩进、提醒行间距或固定 row budget；
- 若展示条目略有减少，继续使用现有“还有 N 项未完成”截断提示。

## 静态验证

实现后执行：

```bash
rg -n "widgetURL|Link\\(|onOpenURL|CFBundleURLTypes|viabar" Viabar ViabarWidget --glob '*.swift' --glob '*.plist'
git diff --check
plutil -lint Viabar/Info.plist
```

由于用户未授权编译或运行测试，本轮不执行 `xcodebuild`。
