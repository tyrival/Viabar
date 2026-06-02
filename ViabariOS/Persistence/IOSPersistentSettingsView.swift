import SwiftData
import SwiftUI

struct IOSPersistentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]

    var body: some View {
        NavigationStack {
            Group {
                if let settings = settingsRecords.first {
                    settingsList(settings)
                } else {
                    ProgressView()
                        .task {
                            AppSettingsStore.ensureDefaultSettings(in: modelContext)
                        }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func settingsList(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings

        return Form {
            Section("功能设置") {
                NavigationLink {
                    IOSPersistentTrashView()
                } label: {
                    Label("回收站", systemImage: "trash")
                }

                NavigationLink {
                    IOSPersistentTemplateManagementView()
                } label: {
                    Label("模板", systemImage: "square.3.layers.3d.middle.filled")
                }
            }

            Section("显示") {
                Picker("主题", selection: themeBinding(settings)) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                Picker("语言", selection: languageBinding(settings)) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker("总览", selection: overviewScopeBinding(settings)) {
                    ForEach(OverviewScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Picker("每周开始于", selection: weekStartDayBinding) {
                    ForEach(WeekStartDay.allCases) { day in
                        Text(day.title).tag(day)
                    }
                }
                Picker("日期格式", selection: dateFormatBinding(settings)) {
                    ForEach(AppDateFormat.allCases) { format in
                        Text(format.example).tag(format)
                    }
                }
            }

            Section {
                Toggle("iCloud 同步", isOn: $settings.syncEnabled)
                Picker("回收站保留期限", selection: trashRetentionBinding) {
                    Text("30 天").tag(TrashRetentionPolicy.thirtyDays)
                    Text("60 天").tag(TrashRetentionPolicy.sixtyDays)
                    Text("90 天").tag(TrashRetentionPolicy.ninetyDays)
                }
            } header: {
                Text("数据")
            } footer: {
                Text("iCloud 同步选项目前仅保留设置状态，云端同步功能尚未启用。")
            }

            Section("关于") {
                LabeledContent("版本号", value: versionText)
                Link(destination: URL(string: "https://t.me/viabarapp")!) {
                    LabeledContent("Telegram", value: "viabarapp")
                }
            }
        }
    }

    private func themeBinding(_ settings: AppSettings) -> Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: settings.theme) ?? .system },
            set: { settings.theme = $0.rawValue }
        )
    }

    private func languageBinding(_ settings: AppSettings) -> Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: settings.language) ?? .system },
            set: { settings.language = $0.rawValue }
        )
    }

    private func overviewScopeBinding(_ settings: AppSettings) -> Binding<OverviewScope> {
        Binding(
            get: { OverviewScope(rawValue: settings.overviewScope) ?? .allProjects },
            set: { settings.overviewScope = $0.rawValue }
        )
    }

    private func dateFormatBinding(_ settings: AppSettings) -> Binding<AppDateFormat> {
        Binding(
            get: { AppDateFormatter.resolvedFormat(for: settings.dateFormat) },
            set: { settings.dateFormat = $0.rawValue }
        )
    }

    private var weekStartDayBinding: Binding<WeekStartDay> {
        Binding(
            get: { WeekStartDaySettingsStore.value() },
            set: { WeekStartDaySettingsStore.set($0) }
        )
    }

    private var trashRetentionBinding: Binding<TrashRetentionPolicy> {
        Binding(
            get: { TrashRetentionSettingsStore.policy() },
            set: { TrashRetentionSettingsStore.set($0) }
        )
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }
}
