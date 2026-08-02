import SwiftUI

struct AISettingsPanel: View {
    @ObservedObject private var aiSettings = AIProviderSettings.shared
    @State private var apiKeyDraft = ""
    @State private var isAPIKeyVisible = false
    @State private var status: Status?
    @State private var isWorking = false
    @State private var usesCustomMaxTokens = false

    private let maxTokenPresets = [4_096, 8_192, 16_384, 32_768, 65_536, 131_072]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup("AI 服务") {
                SettingsRow("服务商") {
                    Picker("", selection: $aiSettings.provider) {
                        Text("OpenAI").tag(AIProviderKind.openAI)
                        Text("DeepSeek").tag(AIProviderKind.deepSeek)
                        Text("自定义兼容接口").tag(AIProviderKind.custom)
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: aiSettings.provider) { _, provider in
                        aiSettings.applyPreset(provider)
                    }
                }

                SettingsDivider()

                SettingsRow("Base URL") {
                    TextField("", text: $aiSettings.baseURLText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                SettingsDivider()

                SettingsRow("API Key") {
                    HStack(spacing: 6) {
                        Group {
                            if isAPIKeyVisible {
                                TextField("", text: $apiKeyDraft)
                            } else {
                                SecureField("", text: $apiKeyDraft)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                .frame(width: 16)
                        }
                        .buttonStyle(.plain)
                        .help(Text(LocalizedStringKey(
                            isAPIKeyVisible ? "隐藏 API Key" : "显示 API Key"
                        )))
                        .accessibilityLabel(Text(LocalizedStringKey(
                            isAPIKeyVisible ? "隐藏 API Key" : "显示 API Key"
                        )))

                        Button("保存") {
                            saveAPIKey()
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingsGroup("模型") {
                SettingsRow("模型") {
                    if aiSettings.fetchedModels.isEmpty {
                        TextField("手动输入模型名称", text: $aiSettings.model)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    } else {
                        Picker("", selection: $aiSettings.model) {
                            ForEach(aiSettings.fetchedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                SettingsDivider()

                SettingsRow(
                    "最大输出 Token",
                    description: "包含模型推理和最终回答"
                ) {
                    HStack(spacing: 6) {
                        Picker("", selection: maxTokensSelection) {
                            ForEach(maxTokenPresets, id: \.self) { value in
                                Text(value.formatted())
                                    .tag(value)
                            }
                            Text("自定义")
                                .tag(-1)
                        }
                        .labelsHidden()
                        .controlSize(.small)

                        if usesCustomMaxTokens {
                            TextField(
                                "Token 数",
                                value: $aiSettings.maxTokens,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 92)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow("操作") {
                    HStack(spacing: 8) {
                        Button("获取模型") {
                            fetchModels()
                        }
                        .disabled(isWorking)

                        Button("测试连接") {
                            testConnection()
                        }
                        .disabled(isWorking)

                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .controlSize(.small)
                }
            }

            statusView
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
        .task {
            usesCustomMaxTokens = !maxTokenPresets.contains(aiSettings.maxTokens)
            if apiKeyDraft.isEmpty {
                apiKeyDraft = (try? await aiSettings.apiKeyAsync()) ?? ""
            }
        }
    }

    private var maxTokensSelection: Binding<Int> {
        Binding(
            get: {
                usesCustomMaxTokens ? -1 : aiSettings.maxTokens
            },
            set: { selection in
                if selection == -1 {
                    usesCustomMaxTokens = true
                } else {
                    usesCustomMaxTokens = false
                    aiSettings.maxTokens = selection
                }
            }
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .none:
            EmptyView()
        case .apiKeySaved:
            Text("API Key 已安全保存")
        case .apiKeySaveFailed:
            Text("API Key 保存失败")
        case .modelsEmpty:
            Text("未获取到模型，可手动输入")
        case .modelsFetched(let count):
            Text("已获取 \(count) 个模型")
        case .modelsFailed:
            Text("获取失败，可手动输入模型名称")
        case .connectionSucceeded:
            Text("连接成功")
        case .connectionFailed:
            Text("连接失败，请检查地址、API Key 和模型")
        }
    }

    private func saveAPIKey() {
        do {
            try aiSettings.saveAPIKey(apiKeyDraft)
            status = .apiKeySaved
        } catch {
            status = .apiKeySaveFailed
        }
    }

    private func fetchModels() {
        isWorking = true
        status = nil
        Task {
            defer { isWorking = false }
            do {
                try aiSettings.saveAPIKey(apiKeyDraft)
                let models = try await OpenAICompatibleService().fetchModels(
                    configuration: aiSettings.configuration(),
                    apiKey: aiSettings.apiKey()
                )
                aiSettings.setFetchedModels(models)
                if aiSettings.model.isEmpty {
                    aiSettings.model = models.first ?? ""
                }
                status = models.isEmpty ? .modelsEmpty : .modelsFetched(models.count)
            } catch {
                aiSettings.clearFetchedModels()
                status = .modelsFailed
            }
        }
    }

    private func testConnection() {
        isWorking = true
        status = nil
        Task {
            defer { isWorking = false }
            do {
                try aiSettings.saveAPIKey(apiKeyDraft)
                try await OpenAICompatibleService().testConnection(
                    configuration: aiSettings.configuration(),
                    apiKey: aiSettings.apiKey()
                )
                status = .connectionSucceeded
            } catch {
                status = .connectionFailed
            }
        }
    }

    private enum Status {
        case apiKeySaved
        case apiKeySaveFailed
        case modelsEmpty
        case modelsFetched(Int)
        case modelsFailed
        case connectionSucceeded
        case connectionFailed
    }
}
