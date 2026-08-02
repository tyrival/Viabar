# Viabar 年度报告 AI 总结实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 macOS 设置中加入 Fringe 同款 OpenAI 兼容配置，并让年度报告基于原始 Markdown 生成、显示和导出只读 AI 总结。

**Architecture:** AI 配置以 `UserDefaults + Keychain` 保存，通过独立 OpenAI 兼容客户端访问模型列表与聊天补全；年度报告只把现有 `reportLines` 作为输入，并在 View 会话内维护结果。生成成功后窗口扩展为严格 50/50 双栏，有结果时导出按钮用 CommuKit 解析器选择器风格的 Popover 路由到两种 Markdown 文档。

**Tech Stack:** Swift 5.10+、SwiftUI、Foundation、Security、UniformTypeIdentifiers、macOS 14.0+、Apple 原生框架。

## Global Constraints

- 使用中文交流。
- 用户未明确要求时不编译、不运行测试；本计划只执行源码静态检查、`git diff --check` 和 `plutil -lint`。
- 不提交代码。
- 不修改任何 `@Model`、SwiftData schema、数据库路径、备份格式、Widget schema 或 CloudKit 配置。
- AI 输入只允许使用当前年份的原始年度报告 Markdown，不读取备忘录或其他隐藏上下文。
- AI 配置使用 `UserDefaults`，API Key 使用 Viabar 独立 Keychain service；AI 结果不持久化。
- 所有新增用户可见文案同步维护英文与简体中文。
- 只复用 Fringe 的设置与 OpenAI 兼容协议，不引入 GlobalText 或其他无关能力。

---

## 文件结构

- 新建 `Viabar/Services/AI/AIProviderTypes.swift`：服务商、连接配置和错误类型。
- 新建 `Viabar/Services/AI/KeychainSecretStore.swift`：最小 Keychain 读写边界。
- 新建 `Viabar/Services/AI/AIProviderSettings.swift`：UserDefaults、Keychain 和运行期模型列表。
- 新建 `Viabar/Services/AI/OpenAICompatibleService.swift`：模型列表与聊天补全 HTTP 协议。
- 新建 `Viabar/Services/AI/YearlyReportAIService.swift`：年度报告提示词与语言约束。
- 新建 `Viabar/Views/Settings/AISettingsPanel.swift`：Fringe 同款 AI 设置内容。
- 新建 `Viabar/Views/Component/MarkdownTextView.swift`：只读 Markdown 渲染与文本选择。
- 修改 `Viabar/Views/Settings/SettingsView.swift`：增加 AI Tab 并接入独立面板。
- 修改 `Viabar/Views/YearlyReportView.swift`：生成状态、50/50 展开、错误、重新生成和双类型导出。
- 修改 `Viabar/en.lproj/Localizable.strings`、`Viabar/zh-Hans.lproj/Localizable.strings`：新增设置、生成、错误和导出文案。

项目使用 `PBXFileSystemSynchronizedRootGroup`，新增 `Viabar/` 下的 Swift 文件不手动编辑 `project.pbxproj`；最终仍执行 `plutil -lint` 确认工程文件有效。

---

### Task 1：建立 AI 配置、Keychain 和错误边界

**Files:**
- Create: `Viabar/Services/AI/AIProviderTypes.swift`
- Create: `Viabar/Services/AI/KeychainSecretStore.swift`
- Create: `Viabar/Services/AI/AIProviderSettings.swift`

**Interfaces:**
- Produces: `AIProviderKind`、`AIProviderConfiguration`、`AIServiceError`、`KeychainSecretStoring`、`KeychainSecretStore`、`@MainActor AIProviderSettings.shared`。
- Consumes: `UserDefaults.standard`、Security framework 的 `SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate` / `SecItemDelete`。

- [ ] **Step 1：定义提供商、配置和统一错误**

`AIProviderTypes.swift` 定义：

```swift
import Foundation

enum AIProviderKind: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case deepSeek
    case custom
    var id: String { rawValue }
}

struct AIProviderConfiguration: Equatable, Sendable {
    let provider: AIProviderKind
    let baseURL: URL
    let model: String
}

enum AIServiceError: Error, Equatable {
    case invalidConfiguration
    case authenticationFailed
    case rateLimited
    case server(statusCode: Int, message: String?)
    case invalidResponse
    case emptyResult
}
```

- [ ] **Step 2：移植最小 Keychain store 并使用 Viabar 独立标识**

保持 Fringe 的协议式封装，但常量必须是：

```swift
static let keychainService = "com.tyrival.Viabar.ai"
static let keychainAccount = "api-key"
```

`read` 对 `errSecItemNotFound` 返回 `nil`；`write` 先更新，找不到再新增；`delete` 对不存在视为成功。不要输出 API Key 或把它写入日志。

- [ ] **Step 3：实现本机配置 store**

`AIProviderSettings` 接口固定为：

```swift
@MainActor
final class AIProviderSettings: ObservableObject {
    static let shared = AIProviderSettings()
    @Published var provider: AIProviderKind
    @Published var baseURLText: String
    @Published var model: String
    @Published private(set) var fetchedModels: [String]

    func applyPreset(_ provider: AIProviderKind)
    func configuration() throws -> AIProviderConfiguration
    func apiKey() throws -> String
    func apiKeyAsync() async throws -> String
    func saveAPIKey(_ value: String) throws
    func clearFetchedModels()
    func setFetchedModels(_ values: [String])
}
```

UserDefaults keys 使用 `viabar.ai.provider`、`viabar.ai.baseURL`、`viabar.ai.model`。预设地址为 `https://api.openai.com` 和 `https://api.deepseek.com`；自定义服务商不覆盖用户输入的 URL。

- [ ] **Step 4：静态确认没有数据模型改动**

```bash
rg -n "AIProviderKind|com\.tyrival\.Viabar\.ai|viabar\.ai\.provider|apiKeyAsync" Viabar/Services/AI --glob '*.swift'
rg -n "@Model|Schema\(" Viabar/Services/AI --glob '*.swift'
git diff --check
```

预期：第一条覆盖所有接口；第二条无输出；格式检查无输出。

---

### Task 2：实现 OpenAI 兼容客户端和年度总结服务

**Files:**
- Create: `Viabar/Services/AI/OpenAICompatibleService.swift`
- Create: `Viabar/Services/AI/YearlyReportAIService.swift`

**Interfaces:**
- Consumes: Task 1 的 `AIProviderConfiguration`、`AIServiceError`。
- Produces: `HTTPTransport`、`URLSessionTransport`、`OpenAICompatibleServicing`、`OpenAICompatibleService`、`YearlyReportAIServicing`、`YearlyReportAIService`。

- [ ] **Step 1：定义可替换 HTTP transport 和服务协议**

```swift
protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol OpenAICompatibleServicing: Sendable {
    func fetchModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String]
    func testConnection(configuration: AIProviderConfiguration, apiKey: String) async throws
    func complete(systemPrompt: String, userContent: String, configuration: AIProviderConfiguration, apiKey: String) async throws -> String
}
```

`URLSessionTransport` 必须验证响应是 `HTTPURLResponse`，否则抛出 `.invalidResponse`。

- [ ] **Step 2：实现端点拼接、授权和模型获取**

端点 helper 接收 `baseURL` 与 `v1/models` 或 `v1/chat/completions`。当 Base URL path 已以 `v1` 结束时移除 suffix 的首个 `v1`，并清除 query/fragment。所有请求设置 60 秒超时、Bearer Authorization 和 JSON Content-Type。

模型列表解码 `{ "data": [{ "id": "..." }] }`，去空、去重并按 localized standard 排序。

- [ ] **Step 3：实现聊天补全和精确错误映射**

请求体固定为：

```swift
ChatRequest(
    model: configuration.model,
    messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: userContent),
    ]
)
```

401/403 映射 `.authenticationFailed`，429 映射 `.rateLimited`，其他非 2xx 映射 `.server(statusCode:message:)`；首个非空 `choices[].message.content` 作为结果，否则 `.emptyResult`。

- [ ] **Step 4：限制年度报告服务输入和输出语言**

```swift
protocol YearlyReportAIServicing: Sendable {
    func summarize(
        originalMarkdown: String,
        outputLanguage: EffectiveAppLanguage,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String
}
```

`YearlyReportAIService` 只把 `originalMarkdown` 传给 `complete`。系统提示词要求：仅根据输入、不得臆造、输出指定语言、只返回 Markdown、不加代码围栏；章节建议为年度概览、主要成果、推进特点、下一年可延续方向，没有依据则省略。

- [ ] **Step 5：静态检查协议与网络契约**

```bash
rg -n 'v1/models|v1/chat/completions|timeoutInterval = 60|Bearer|systemPrompt|originalMarkdown' Viabar/Services/AI --glob '*.swift'
rg -n 'Memo|memos|modelContext|SwiftData' Viabar/Services/AI/YearlyReportAIService.swift
git diff --check
```

预期：第一条覆盖完整调用链；第二条无输出，证明总结服务未读取备忘录或数据库；格式检查无输出。

---

### Task 3：增加 Fringe 同款 AI 设置 Tab

**Files:**
- Create: `Viabar/Views/Settings/AISettingsPanel.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: Task 1 的 `AIProviderSettings`，Task 2 的 `OpenAICompatibleService`，现有 `SettingsGroup` / `SettingsRow` / `SettingsDivider`。
- Produces: `AISettingsPanel` 和 `SettingsCategory.ai`。

- [ ] **Step 1：增加 AI Tab**

在 `SettingsCategory` 中加入：

```swift
case ai = "AI"
```

图标返回 `sparkles`；`SettingsDetailView.panelContent` 的 `.ai` 分支显示 `AISettingsPanel()`。不把 AI 状态加入 `AppSettings`。

- [ ] **Step 2：实现 AI 服务配置区**

`AISettingsPanel` 使用：

```swift
@ObservedObject private var aiSettings = AIProviderSettings.shared
@State private var apiKeyDraft = ""
@State private var isAPIKeyVisible = false
@State private var statusKey: LocalizedStringKey?
@State private var statusCount: Int?
@State private var isWorking = false
```

第一组严格包含服务商 Picker、Base URL、API Key、安全显示切换和保存按钮。选择预设服务商调用 `applyPreset`；首次出现通过 `apiKeyAsync()` 读取密钥，避免同步阻塞设置窗口。

- [ ] **Step 3：实现模型区和连接动作**

没有模型列表时显示手动输入 TextField；有列表时显示 Picker。获取模型和测试连接前先保存 draft API Key，然后读取配置和 Keychain；请求期间两个按钮禁用并显示小型 `ProgressView`。

状态不得拼接未本地化的完整句子。模型数量使用格式 key：

```text
"已获取 %lld 个模型"
```

- [ ] **Step 4：补齐设置本地化**

至少加入：AI、AI 服务、服务商、自定义兼容接口、模型、手动输入模型名称、获取模型、测试连接、保存、显示 API Key、隐藏 API Key、API Key 已安全保存、API Key 保存失败、未获取到模型可手动输入、获取失败可手动输入、连接成功、连接失败以及模型数量格式。

- [ ] **Step 5：静态验证设置结构**

```bash
rg -n 'case ai|AISettingsPanel|AIProviderSettings\.shared|apiKeyAsync|fetchModels|testConnection' Viabar/Views/Settings Viabar/Services/AI --glob '*.swift'
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git diff --check
```

预期：AI Tab、异步密钥读取和两种操作均存在；两个 strings 文件均为 OK；格式检查无输出。

---

### Task 4：提供只读 Markdown 展示组件

**Files:**
- Create: `Viabar/Views/Component/MarkdownTextView.swift`

**Interfaces:**
- Produces: `MarkdownTextView(markdown: String)`、文件私有的 `MarkdownBlock` 与 block parser。
- Consumes: Foundation `AttributedString(markdown:options:)` 与 SwiftUI 原生布局。

- [ ] **Step 1：实现只读 Markdown 渲染**

先按行解析块级结构，至少识别 `#`/`##`/`###` 标题、`-`/`*` 无序列表、数字有序列表、`>` 引用、三反引号代码块和普通段落。连续普通行合并为同一段；空行结束当前段落。每个 block 内再用 `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))` 渲染粗体、斜体、行内代码和链接；解析失败时回退原文，不得丢失模型输出。

文件私有类型和函数签名固定为：

```swift
private enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case unordered(text: String)
    case ordered(number: String, text: String)
    case quote(text: String)
    case code(String)
    case paragraph(String)
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock]
}
```

```swift
struct MarkdownTextView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .headline : .subheadline.bold())
        case let .unordered(text):
            HStack(alignment: .firstTextBaseline) { Text("•"); inlineText(text) }
        case let .ordered(number, text):
            HStack(alignment: .firstTextBaseline) { Text("\(number)."); inlineText(text) }
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.secondary).frame(width: 3)
                inlineText(text).foregroundStyle(.secondary)
            }
        case let .code(text):
            Text(verbatim: text)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        case let .paragraph(text):
            inlineText(text)
        }
    }

    private func inlineText(_ source: String) -> Text {
        guard let value = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return Text(verbatim: source) }
        return Text(value)
    }
}
```

- [ ] **Step 2：保持组件职责单一**

标题使用分级字体；列表行保留项目符号或序号和缩进；引用使用左侧竖线与 secondary 文字；代码块使用等宽字体和系统填充背景。组件内部不负责滚动、网络请求、编辑、复制按钮或文件导出；这些职责留给 `YearlyReportView`。

- [ ] **Step 3：静态确认回退和文本选择**

```bash
rg -n 'enum MarkdownBlock|inlineOnlyPreservingWhitespace|unordered|ordered|quote|code|textSelection\(\.enabled\)' Viabar/Views/Component/MarkdownTextView.swift
git diff --check
```

预期：块级结构、行内 Markdown、原文回退和文本选择契约均存在。

---

### Task 5：接入年度报告生成、50/50 展开和请求生命周期

**Files:**
- Modify: `Viabar/Views/YearlyReportView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: Task 1 的 `AIProviderSettings`，Task 2 的 `YearlyReportAIServicing`，Task 4 的 `MarkdownTextView`。
- Produces: 年度报告 AI 请求状态、严格等宽双栏、重新生成和内联错误显示。

- [ ] **Step 1：增加可控状态和服务注入**

新增状态：

```swift
@State private var aiSummaryMarkdown: String?
@State private var aiErrorKey: LocalizedStringKey?
@State private var isGeneratingAISummary = false
@State private var aiTask: Task<Void, Never>?
@State private var isExportChoicePresented = false
```

为静态可替换性给 initializer 增加默认服务参数，并使用私有属性保存：

```swift
init(
    projects: [Project],
    language: EffectiveAppLanguage,
    aiService: any YearlyReportAIServicing = YearlyReportAIService()
)
```

- [ ] **Step 2：扩大默认窗口并加入 AI 按钮**

默认 frame 改为 `width: 720, height: 640`。年份行最右侧加入 `AI 总结` / `重新生成` 按钮；请求时显示 `ProgressView` 并禁用，空报告时禁用。

- [ ] **Step 3：实现只使用原始 Markdown 的生成流程**

点击时捕获：

```swift
let requestedYear = selectedYear
let originalMarkdown = reportLines.joined(separator: "\n")
```

读取 `AIProviderSettings.shared.configuration()` 和 API Key 后调用：

```swift
try await aiService.summarize(
    originalMarkdown: originalMarkdown,
    outputLanguage: language,
    configuration: configuration,
    apiKey: apiKey
)
```

响应写回前检查 `!Task.isCancelled && selectedYear == requestedYear`。首次失败不展开；重新生成失败保留旧 `aiSummaryMarkdown`。错误映射为配置不完整、认证失败、限流、服务失败、空结果五类本地化 key。

- [ ] **Step 4：实现年份切换和关闭取消**

`onChange(of: selectedYear)` 中取消 `aiTask`，清空结果、错误和生成状态。`onDisappear` 取消任务。不得让旧年份响应写入当前状态。

- [ ] **Step 5：实现严格 50/50 双栏**

无结果时保持单栏。存在结果时窗口宽度切换为 `1120`，内容区使用：

```swift
GeometryReader { proxy in
    HStack(spacing: 0) {
        originalReportContent
            .frame(width: proxy.size.width / 2)
        Divider()
        aiSummaryContent
            .frame(width: proxy.size.width / 2)
    }
}
```

实现时需把 Divider 的宽度从可分配内容宽度中扣除，最终两侧 frame 使用同一个计算值 `(proxy.size.width - dividerWidth) / 2`，保证视觉内容严格等宽。左右分别包裹 ScrollView；右侧标题为“AI 总结”和“Markdown”，正文使用 `MarkdownTextView`。

- [ ] **Step 6：补齐年度报告状态文案并静态核对**

新增 AI 总结、重新生成、正在生成、配置不完整、认证失败、请求过于频繁、生成失败、返回内容为空、Markdown 等中英文 key。

```bash
rg -n 'originalMarkdown = reportLines|selectedYear == requestedYear|aiTask\?\.cancel|1120|/ 2|MarkdownTextView|重新生成' Viabar/Views/YearlyReportView.swift
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git diff --check
```

预期：输入来源、过期响应保护、取消、双栏和 Markdown 展示全部存在；本地化文件为 OK。

---

### Task 6：实现 CommuKit 风格双类型导出 Popover

**Files:**
- Modify: `Viabar/Views/YearlyReportView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: 原始 `reportLines`、Task 5 的 `aiSummaryMarkdown`、现有 `YearlyReportDocument`。
- Produces: `YearlyReportExportKind`、导出动作 Popover、按类型变化的内容和文件名。

- [ ] **Step 1：定义导出类型和单一 exporter 状态**

```swift
private enum YearlyReportExportKind {
    case original
    case aiSummary
}

@State private var exportKind: YearlyReportExportKind = .original
```

`exportContent` 和 `exportFilename` 根据 `exportKind` 返回内容。原始文件名保持现状；AI 文件名使用本地化“AI 总结”标签生成 `Viabar_<标签>_<年份>.md`。

- [ ] **Step 2：保持无 AI 结果时的旧行为**

导出按钮动作：当 `aiSummaryMarkdown == nil` 时设置 `.original` 并直接显示现有 `fileExporter`；不得先弹 Popover。

- [ ] **Step 3：实现有结果时的选择气泡**

有结果时显示 `.popover(isPresented:arrowEdge: .bottom)`。内容参考 CommuKit `PipelineRunnerView.pipelinePicker`：固定宽度、`VStack(spacing: 0)`、每行图标 + 标题 + Spacer、32pt 行高、7pt 连续圆角和 hover 底色。

两个动作使用 `doc.text` / `sparkles` 图标，点击后先关闭 Popover，再在下一主线程周期设置 `exportKind` 和 `isExporting = true`。不加入搜索框，不显示勾号，因为这是即时动作而非持久选择。

- [ ] **Step 4：让 fileExporter 读取当前类型**

```swift
.fileExporter(
    isPresented: $isExporting,
    document: YearlyReportDocument(content: exportContent),
    contentType: .plainText,
    defaultFilename: exportFilename
)
```

选择 AI 时必须使用已经生成的 `aiSummaryMarkdown`，不得重新请求模型。

- [ ] **Step 5：补齐导出本地化并静态验证**

新增“导出原始年报”“导出 AI 总结”英文和简体中文 key。

```bash
rg -n 'YearlyReportExportKind|exportContent|exportFilename|popover\(|doc\.text|sparkles|导出原始年报|导出 AI 总结' Viabar/Views/YearlyReportView.swift Viabar/*.lproj/Localizable.strings
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git diff --check
```

预期：无结果直接导出、有结果两项选择、内容与文件名路由均可静态追踪。

---

### Task 7：完成全链路静态验收

**Files:**
- Verify only: `Viabar/Services/AI/*.swift`
- Verify only: `Viabar/Views/Settings/SettingsView.swift`
- Verify only: `Viabar/Views/Settings/AISettingsPanel.swift`
- Verify only: `Viabar/Views/Component/MarkdownTextView.swift`
- Verify only: `Viabar/Views/YearlyReportView.swift`
- Verify only: `Viabar/en.lproj/Localizable.strings`
- Verify only: `Viabar/zh-Hans.lproj/Localizable.strings`
- Verify only: `Viabar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Tasks 1-6 的全部实现。
- Produces: 不依赖编译或测试的静态验收证据。

- [ ] **Step 1：核对 AI 配置与年度报告调用链**

```bash
rg -n 'case ai|AIProviderSettings|OpenAICompatibleService|YearlyReportAIService|originalMarkdown|MarkdownTextView|YearlyReportExportKind' Viabar --glob '*.swift'
```

预期：设置、存储、网络、年度提示、展示和导出均形成唯一调用链。

- [ ] **Step 2：确认没有 schema 和备份改动**

```bash
git diff --name-only
git diff -- Viabar/Models Viabar/System ViabarWidget Viabar/Services/BackupService.swift Viabar/Models/BackupSnapshot.swift
```

预期：文件清单仅包含计划所列文件；第二条无输出。

- [ ] **Step 3：检查本地化与工程文件**

```bash
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
plutil -lint Viabar.xcodeproj/project.pbxproj
```

预期：三个文件均报告 `OK`。

- [ ] **Step 4：检查格式与最终 diff**

```bash
git diff --check
git status --short
git diff --stat
```

预期：`git diff --check` 无输出；状态中不包含编译产物、数据库文件或无关用户改动。

- [ ] **Step 5：明确未验证项**

最终交付说明必须写明：未编译、未运行测试、未做真实 AI 联网请求、未验证运行时窗口动画与 Popover 定位；这些项目只有用户后续明确授权后才能执行。
