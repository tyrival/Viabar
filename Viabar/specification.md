App 产品设计与技术规范书 (PRD) —— 轻量化里程碑管理工具

## 1. 产品概述与核心理念
* **定位**：一款聚焦于“多项目全局进度”与“里程碑管理”的轻量化生产力工具，面向独立开发者或多项目负责人。
* **核心理念**：降噪、聚焦、保持推进惯性。摒弃传统工单式细粒度任务管理，转而面向“里程碑”与“上下文沉淀”。
* **生态目标**：基于 Apple 生态（macOS + iOS），利用系统原生组件与极致的键盘友好交互，通过 iCloud 实现秒级静默同步。

---

## 2. 技术栈与架构约束 (Strict Tech Stack)
AI 代理在生成任何代码、UI 或底层逻辑时，**必须严格遵守**以下技术栈约束，拒绝引入任何过时或不相关的第三方库：

* **开发语言**：Swift 5.10+
* **UI 框架**：SwiftUI (完全遵循 Apple Human Interface Guidelines - HIG)
* **数据持久化**：SwiftData (或 CoreData)
* **多端同步**：iCloud + CloudKit (原生 Silent Push Notification 联动)
* **系统集成**：WidgetKit (桌面组件) / MenuBar Extra (macOS 菜单栏)
* **目标平台**：macOS 14.0+ / iOS 17.0+

---

## 3. 功能架构与详细设计

### 3.1 界面布局与交互拓扑 (Layout & UX)
应用采用响应式三栏/双栏架构，严禁复杂的层级跳转，保持视觉降噪：

1. **左侧边栏 (Sidebar)**：
   * 聚合展示所有项目列表。
   * 每个项目条目右侧必须直观显示基于 **Rollup 算法** 动态计算的环形/条形进度条。
2. **中央主面板 (Main Panel - 双栏平铺)**：
   * **左栏（任务/里程碑区）**：
     * 垂直时间线流，仅展示两级结构（里程碑 $\rightarrow$ 核心子任务）。
     * 顶部常驻快捷切换开关（Toggle）：`[显示/隐藏已完成]`。支持按项目/模板级别配置其默认初始状态。
   * **右栏（备忘/上下文区）**：
     * **上部**：流式备忘录（Timeline 形式，按时间倒序排列，支持多条追加）。
     * **下部**：常驻极简输入框（激活即可输入，`Cmd + Enter` 或点击发送直接追加到上方）。

### 3.2 核心算法与专项设计 (Core Logic)

#### 3.2.1 进度动态加权计算机制 (Rollup Calculation)
应用内的项目进度严禁手动填写，必须由系统通过以下两级任务树算法自动计算渲染：

* **计算公式**：
  设一个项目包含 $N$ 个一级里程碑。每个一级里程碑的权重均等，即为 $\frac{1}{N}$。
  1. 若某个里程碑**不包含子任务**：完成时得分 $1.0$，未完成得分 $0$。
  2. 若某个里程碑**包含 $M$ 个子任务**：该里程碑的得分 $S = \frac{\text{已完成子任务数}}{M}$。
  3. 项目最终总进度 $Progress = \sum_{i=1}^{N} \frac{S_i}{N}$。

* **测试用例 (AI 边界单测依据)**：
  > 假设项目 A 共有 10 个一级里程碑任务（每个占比 10%）。
  > * 前 6 个里程碑已完全搞定 $\rightarrow$ 贡献进度：$6 \times 10\% = 60\%$。
  > * 第 7 个里程碑包含 8 个子任务，目前完成了 6 个 $\rightarrow$ 该里程碑自身进度为 $\frac{6}{8} = 75\%$，折算到项目总进度为 $75\% \times 10\% = 7.5\%$。
  > * 其余 3 个里程碑未动。
  > * **预期结果**：Dashboard 及侧边栏显示的该项目总进度必须精确等于 **67.5%**。

#### 3.2.2 独立通知类封装与上下文穿透 (Notification Architecture)
为确保提醒功能的灵活性与项目连续性，必须将通知逻辑单独封装为一个通用类/结构体，并具备“上下文穿透”能力。

* **实体封装 (`NotificationScheduler`)**：
  * **单次提醒**：支持指定具体时间戳（`Date`）。
  * **重复提醒**：支持周期性循环策略（每日、每周特定几天、每 N 天、每月固定日期）。
  * **附加属性**：可作为独立可选属性（Optional）挂载在 `Project` 或 `Milestone` 上。
* **项目级提醒的“上下文穿透”机制**：
  * 当一个 `NotificationScheduler` 挂载在 **项目(Project) 级别** 并触发系统通知时，系统禁止直接显示空泛的项目名称。
  * **业务逻辑**：触发通知时，底层必须自动检索该项目当前数据模型中**最顶端、未完成（`isCompleted == false`）的第一个里程碑任务**（若该里程碑包含子任务，则精确定位到第一个未完成的子任务）。
  * **通知文案组装模板**：
    `"项目【\(project.title)】正待推进（当前进度 \(project.progress * 100)%）。下一步核心待办：【\(topUncompletedTask.title)】，请点击继续。"`

#### 3.2.3 全局模糊搜索抽屉 (Global Search & Flash)
* **交互行为**：点击右上角快捷菜单放大镜或按下快捷键 `Cmd + F` 弹出右侧搜索抽屉。
* **检索范围**：全局模糊匹配，同时检索所有项目的“里程碑名称”、“子任务名称”以及“备忘录文本内容”。
* **穿透跳转与高亮闪烁**：点击搜索结果中的任意条目，主界面自动切换至对应项目。定位到具体的任务卡片或备忘录卡片上，并对该 UI 组件执行 **3 次呼吸闪烁动画 (Custom Breath Animation)**，快速引导用户视觉。

#### 3.2.4 自动化报告生成引擎 (Report Generator)
* **周报/月报**：一键提取选定周期内，状态变更为 `isCompleted == true` 的所有里程碑与子任务。
* **下周计划**：自动提取当前周期内 `isCompleted == false` 的、或紧邻的下一个未完成里程碑。
* **输出规范**：一键生成纯文本（标准 Markdown 格式，方便复制），同时支持系统原生渲染导出为标准 PDF。

#### 3.2.5 生态常驻入口
* **macOS 菜单栏 (MenuBar Extra)**：点击状态栏图标下拉呈现极简列表，显示各项目进度条及最顶端未完成任务，支持点击唤起主程序。
* **桌面组件 (WidgetKit)**：设计中/大号组件，展示多项目进度条及最新的项目唤醒穿透提示。

### 3.3 目录结构

Viabar/
├── specification.md             # 你的最高灵魂约束文档（放在根目录）
├── ViabarApp.swift              # App 启动入口，配置 SwiftData Container
├── Assets.assets                # 图标、资产文件
│
├── 📂 Models/                   # 1. 数据模型层（唯一真理源）
│   ├── Project.swift            # 项目模型（包含模型定义与 Rollup 算法）
│   ├── Milestone.swift          # 里程碑模型
│   ├── SubTask.swift            # 子任务模型
│   └── Memo.swift               # 备忘录模型
│
├── 📂 Services/                 # 2. 核心业务逻辑层（纯 Swift 逻辑）
│   └── NotificationScheduler.swift # 独立封装的通知与上下文穿透调度类
│
├── 📂 Views/                    # 3. 视图层（响应式 SwiftUI 积木）
│   ├── Dashboard/               # Dashboard 模块
│   │   └── DashboardView.swift  # 全局多项目平铺看板
│   ├── MainPanel/               # 主管理面板模块
│   │   ├── MainSplitView.swift  # 双栏/三栏响应式骨架
│   │   ├── MilestoneListView.swift # 左栏：里程碑与子任务列表
│   │   └── MemoTimelineView.swift  # 右栏：流式备忘录及极简输入框
│   └── Component/               # 通用组件抽离
│       ├── SearchDrawerView.swift  # 全局模糊搜索抽屉
│       └── BreathFlashModifier.swift # 3次呼吸闪烁动画的 ViewModifier
│
└── 📂 System/                   # 4. 系统集成扩展（Phase 3 进阶）
    ├── MenuBarManager.swift     # macOS 菜单栏常驻控制
    └── ViabarWidget.swift       # 桌面组件 WidgetKit 支持


---

## 4. 统一数据结构定义 (Unified Schema)
AI 代理在设计 SwiftData 模型或进行 JSON 解析时，必须严格参考并以此数据结构为“唯一真理源”：

```json
{
  "project_id": "uuid_v4",
  "title": "项目名称",
  "progress": 0.675, 
  "config": {
    "hide_completed": true
  },
  "project_reminder": {
    "reminder_id": "uuid_v4",
    "type": "repeating", 
    "fire_time": "10:00",
    "repeat_interval_days": 3,
    "last_triggered_timestamp": 1778858400
  },
  "milestones": [
    {
      "milestone_id": "uuid_v4",
      "title": "里程碑任务名称",
      "is_completed": false,
      "order_index": 0,
      "task_reminder": {
        "reminder_id": "uuid_v4",
        "type": "single",
        "fire_timestamp": 1779184800
      },
      "sub_tasks": [
        { "task_id": "uuid_v4", "title": "子任务1", "is_completed": true, "order_index": 0 },
        { "task_id": "uuid_v4", "title": "子任务2", "is_completed": true, "order_index": 1 },
        { "task_id": "uuid_v4", "title": "最顶端未完成的子任务", "is_completed": false, "order_index": 2 }
      ]
    }
  ],
  "memos": [
    {
      "memo_id": "uuid_v4",
      "content": "细节备忘文本信息",
      "created_at_timestamp": 1779125400
    }
  ]
}
```

---

## 5. 开发路线图与约束细分 (Roadmap & Prompts)

### Phase 1: 核心数据模型与进度算法验证
* 目标：完成 SwiftData 实体类设计，完美通过 Rollup 进度动态计算的单元测试。
* AI 引导命令："请读取 SPECIFICATION.md，基于第 4 节的 Unified Schema 创建 SwiftData 模型，并严格按照 3.2.1 节实现项目的进度自动计算 Extension，编写配套单测验证 67.5% 的用例。"

### Phase 2: 双栏主界面构建与本地通知类封装
* 目标：搭建 macOS/iOS 响应式主界面，完成 NotificationScheduler 独立类的封装，实现项目级提醒的上下文穿透逻辑。
* AI 引导命令："请参考 SPECIFICATION.md 中 3.1 和 3.2.2 节，用 SwiftUI 编写双栏主面板视图，并封装 NotificationScheduler 类。重点实现当项目通知触发时，自动找出最顶端未完成任务的穿透逻辑。"

### Phase 3: 全局模糊搜索抽屉、报告引擎与外延生态
* 目标：实现带有 3 次呼吸闪烁动画的全局搜索、一键导出 Markdown 周报、以及 WidgetKit/MenuBar 集成。
