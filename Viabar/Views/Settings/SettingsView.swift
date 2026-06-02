import AppKit
import SwiftData
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case display = "显示"
    case shortcuts = "快捷键"
    case data = "数据"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .display: "display"
        case .shortcuts: "keyboard"
        case .data: "arrow.trianglehead.2.clockwise.rotate.90"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    var onMenuBarEnabledChange: (Bool) -> Void = { _ in }
    var onMenuBarIconChange: (MenuBarIcon) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var selection: SettingsCategory = .general

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    var body: some View {
        Group {
            if let settings = settingsRecords.first {
                TabView(selection: $selection) {
                    ForEach(SettingsCategory.allCases) { category in
                        SettingsDetailView(
                            category: category,
                            settings: settings,
                            onMenuBarEnabledChange: onMenuBarEnabledChange,
                            onMenuBarIconChange: onMenuBarIconChange
                        )
                            .tabItem {
                                Label(LocalizedStringKey(category.rawValue), systemImage: category.icon)
                            }
                            .tag(category)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        AppSettingsStore.ensureDefaultSettings(in: modelContext)
                    }
            }
        }
        .frame(width: 660, height: 500)
        .environment(\.locale, effectiveLanguage.locale)
    }
}

private struct SettingsDetailView: View {
    private enum ShortcutAction {
        case toggleMainPanel
        case openSearch
    }

    let category: SettingsCategory
    @Bindable var settings: AppSettings
    let onMenuBarEnabledChange: (Bool) -> Void
    let onMenuBarIconChange: (MenuBarIcon) -> Void
    @Environment(ServiceContainer.self) private var container
    @Environment(AppRuntimeController.self) private var runtimeController
    @State private var recordingShortcut: ShortcutAction?
    @State private var settingsErrorMessage: LocalizedStringKey?
    @State private var showsBackupBrowser = false
    @State private var trashRetentionPolicy = TrashRetentionSettingsStore.policy().rawValue

    private var backupService: BackupService? {
        container.backupService
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settings.language)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                panelContent
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 22)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            recordingShortcut = nil
        }
        .onAppear {
            if category == .general {
                runtimeController.launchAtLogin.refresh()
                settings.launchAtLogin = runtimeController.launchAtLogin.isEnabled
            }
            if category == .data {
                trashRetentionPolicy = TrashRetentionSettingsStore.policy().rawValue
                try? backupService?.refreshBackups(settings: settings)
            }
        }
        .alert("无法应用设置", isPresented: settingsErrorBinding) {
            Button("好", role: .cancel) {
                settingsErrorMessage = nil
            }
        } message: {
            if let settingsErrorMessage {
                Text(settingsErrorMessage)
            }
        }
        .sheet(isPresented: $showsBackupBrowser) {
            if let backupService {
                BackupBrowserView(backupService: backupService, settings: settings)
            }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch category {
        case .general:
            generalPanel
        case .display:
            displayPanel
        case .shortcuts:
            shortcutsPanel
        case .data:
            dataPanel
        case .about:
            aboutPanel
        }
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup("启动") {
                SettingsRow("开机启动") {
                    settingsSwitch(launchAtLoginBinding)
                }
            }

            SettingsGroup("菜单栏组件") {
                SettingsRow("启用") {
                    settingsSwitch(menuBarEnabledBinding)
                }
                SettingsDivider()
                SettingsRow("图标") {
                    Picker("图标", selection: menuBarIconBinding) {
                        ForEach(MenuBarIcon.allCases) { icon in
                            MenuBarIconImage(icon: icon)
                                .font(.system(size: 16))
                                .accessibilityLabel(Text(icon.rawValue))
                                .tag(icon)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 188, alignment: .trailing)
                }
                SettingsDivider()
                SettingsRow("项目") {
                    Picker("项目", selection: menuBarProjectScopeBinding) {
                        ForEach(MenuBarProjectScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                }
                SettingsDivider()
                SettingsRow("功能") {
                    Picker("功能", selection: menuBarContentModeBinding) {
                        ForEach(MenuBarContentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                }
            }
        }
    }

    private var displayPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup("外观") {
                SettingsRow("主题") {
                    Picker("主题", selection: themeBinding) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                }
                SettingsDivider()
                SettingsRow("语言") {
                    Picker("语言", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                }
            }

            SettingsGroup("视图") {
                SettingsRow("总览") {
                    Picker("总览", selection: overviewScopeBinding) {
                        ForEach(OverviewScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                }
                SettingsDivider()
                SettingsRow("每周开始于") {
                    Picker("每周开始于", selection: weekStartDayBinding) {
                        ForEach(WeekStartDay.allCases) { day in
                            Text(day.title).tag(day)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                }
                SettingsDivider()
                SettingsRow("日期格式") {
                    Picker("日期格式", selection: dateFormatBinding) {
                        ForEach(AppDateFormat.allCases) { format in
                            Text(format.example).tag(format)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 188, alignment: .trailing)
                }
            }
        }
    }

    private var shortcutsPanel: some View {
        SettingsGroup("应用操作") {
            SettingsRow("显示 / 隐藏主面板") {
                ShortcutRecorderField(
                    accessibilityTitle: "显示或隐藏主面板快捷键",
                    value: settings.toggleMainPanelShortcut,
                    isRecording: recordingBinding(for: .toggleMainPanel)
                ) {
                    recordShortcut($0, for: .toggleMainPanel)
                }
            }
            SettingsDivider()
            SettingsRow("打开搜索框") {
                ShortcutRecorderField(
                    accessibilityTitle: "打开搜索框快捷键",
                    value: settings.openSearchShortcut,
                    isRecording: recordingBinding(for: .openSearch)
                ) {
                    recordShortcut($0, for: .openSearch)
                }
            }
        }
    }

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup("数据同步") {
                SettingsRow("iCloud") {
                    settingsSwitch($settings.syncEnabled)
                }
            }

            SettingsGroup("回收站") {
                SettingsRow("保留期限", description: "过期的将从本地和云端永久抹除") {
                    Picker("", selection: $trashRetentionPolicy) {
                        Text("30天").tag(TrashRetentionPolicy.thirtyDays.rawValue)
                        Text("60天").tag(TrashRetentionPolicy.sixtyDays.rawValue)
                        Text("90天").tag(TrashRetentionPolicy.ninetyDays.rawValue)
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 96, alignment: .trailing)
                    .onChange(of: trashRetentionPolicy) { _, rawValue in
                        TrashRetentionSettingsStore.set(TrashRetentionPolicy.resolve(rawValue))
                    }
                }
            }

            SettingsGroup("数据备份") {
                SettingsRow("启用") {
                    settingsSwitch(backupEnabledBinding)
                }
                SettingsDivider()
                SettingsRow("备份路径") {
                    HStack(spacing: 6) {
                        TextField("备份路径", text: $settings.backupPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(width: 190)

                        Button("选择...") {
                            selectBackupFolder()
                        }
                        .controlSize(.small)
                    }
                }
                SettingsDivider()
                SettingsRow("Backup") {
                    HStack(spacing: 8) {
                        Button("立即备份") {
                            createBackup()
                        }
                        Button("浏览备份") {
                            browseBackups()
                        }
                    }
                    .controlSize(.small)
                }
            }

            BackupPolicySummaryView(
                language: effectiveLanguage,
                latestBackupText: backupService?.latestBackupText(language: effectiveLanguage)
                    ?? AppLocalization.string("暂无备份", language: effectiveLanguage)
            )
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow("版本号") {
                    Text(versionText)
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow("自动更新", description: "保持 Viabar 为最新版本") {
                    settingsSwitch(automaticallyChecksForUpdatesBinding)
                }
            }

            SettingsGroup {
                SettingsRow("Telegram") {
                    Button("viabarapp") {
                        NSWorkspace.shared.open(URL(string: "https://t.me/viabarapp")!)
                    }
                    .controlSize(.small)
                    .buttonStyle(.link)
                }
            }
        }
    }

    private func placeholderRow(_ title: LocalizedStringKey) -> some View {
        SettingsRow(title) {
            Button("即将开放") {}
                .controlSize(.small)
                .disabled(true)
        }
    }

    private func settingsSwitch(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private func selectBackupFolder() {
        let panel = NSOpenPanel()
        let language = AppLanguage.effectiveLanguage(storedValue: settings.language)
        panel.title = AppLocalization.string("选择备份文件夹", language: language)
        panel.prompt = AppLocalization.string("选择", language: language)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        do {
            try backupService?.authorizeBackupDirectory(directoryURL, settings: settings)
            settings.backupEnabled = true
            backupService?.setAutomaticBackupEnabled(true, settings: settings)
        } catch {
            settingsErrorMessage = "无法读取备份路径，请检查文件夹权限。"
        }
    }

    private func recordingBinding(for action: ShortcutAction) -> Binding<Bool> {
        Binding(
            get: { recordingShortcut == action },
            set: { isRecording in
                recordingShortcut = isRecording ? action : nil
            }
        )
    }

    private var settingsErrorBinding: Binding<Bool> {
        Binding(
            get: { settingsErrorMessage != nil },
            set: { if !$0 { settingsErrorMessage = nil } }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { enabled in
                do {
                    try runtimeController.launchAtLogin.setEnabled(enabled)
                    settings.launchAtLogin = runtimeController.launchAtLogin.isEnabled
                } catch {
                    settings.launchAtLogin = runtimeController.launchAtLogin.isEnabled
                    settingsErrorMessage = "无法更新开机启动设置，请在系统设置中检查登录项权限。"
                }
            }
        )
    }

    private var menuBarEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.menuBarComponentEnabled },
            set: { enabled in
                settings.menuBarComponentEnabled = enabled
                onMenuBarEnabledChange(enabled)
            }
        )
    }

    private func recordShortcut(_ storedValue: String, for action: ShortcutAction) {
        let previousValue: String
        switch action {
        case .toggleMainPanel:
            previousValue = settings.toggleMainPanelShortcut
            settings.toggleMainPanelShortcut = storedValue
        case .openSearch:
            previousValue = settings.openSearchShortcut
            settings.openSearchShortcut = storedValue
        }

        do {
            try runtimeController.configureShortcuts(from: settings)
        } catch {
            switch action {
            case .toggleMainPanel:
                settings.toggleMainPanelShortcut = previousValue
            case .openSearch:
                settings.openSearchShortcut = previousValue
            }
            try? runtimeController.configureShortcuts(from: settings)
            settingsErrorMessage = "该快捷键无法注册或已被另一项操作占用，请选择其他组合键。"
        }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: settings.theme) ?? .system },
            set: { theme in
                settings.theme = theme.rawValue
                AppAppearanceController.apply(theme)
            }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: settings.language) ?? .system },
            set: { settings.language = $0.rawValue }
        )
    }

    private var overviewScopeBinding: Binding<OverviewScope> {
        Binding(
            get: { OverviewScope(rawValue: settings.overviewScope) ?? .allProjects },
            set: { settings.overviewScope = $0.rawValue }
        )
    }

    private var menuBarIconBinding: Binding<MenuBarIcon> {
        Binding(
            get: { MenuBarIcon.resolve(settings.menuBarIcon) },
            set: { icon in
                settings.menuBarIcon = icon.rawValue
                onMenuBarIconChange(icon)
            }
        )
    }

    private var menuBarProjectScopeBinding: Binding<MenuBarProjectScope> {
        Binding(
            get: { MenuBarProjectScope.resolve(settings.menuBarProjectScope) },
            set: { settings.menuBarProjectScope = $0.rawValue }
        )
    }

    private var menuBarContentModeBinding: Binding<MenuBarContentMode> {
        Binding(
            get: { MenuBarContentMode.resolve(settings.menuBarContentMode) },
            set: { settings.menuBarContentMode = $0.rawValue }
        )
    }

    private var dateFormatBinding: Binding<AppDateFormat> {
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

    private var backupEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.backupEnabled },
            set: { enabled in
                if enabled {
                    if settings.backupPath.isEmpty {
                        selectBackupFolder()
                    } else {
                        settings.backupEnabled = true
                        backupService?.setAutomaticBackupEnabled(true, settings: settings)
                    }
                } else {
                    settings.backupEnabled = false
                    backupService?.setAutomaticBackupEnabled(false, settings: settings)
                }
            }
        )
    }

    private var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { settings.automaticallyChecksForUpdates },
            set: { enabled in
                settings.automaticallyChecksForUpdates = enabled
                container.updateService?.automaticallyChecksForUpdates = enabled
            }
        )
    }

    private func createBackup() {
        do {
            try backupService?.createBackup(settings: settings)
        } catch BackupServiceError.authorizationRequired {
            settingsErrorMessage = "请先选择备份文件夹以授予写入权限。"
        } catch {
            settingsErrorMessage = "无法创建备份，请检查备份路径权限。"
        }
    }

    private func browseBackups() {
        do {
            try backupService?.refreshBackups(settings: settings)
            showsBackupBrowser = true
        } catch BackupServiceError.authorizationRequired {
            settingsErrorMessage = "请先选择备份文件夹以授予写入权限。"
        } catch {
            settingsErrorMessage = "无法读取备份路径，请检查文件夹权限。"
        }
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }
}

private struct MenuBarIconImage: View {
    let icon: MenuBarIcon

    @ViewBuilder
    var body: some View {
        if let systemImageName = icon.systemImageName {
            Image(systemName: systemImageName)
        } else if let assetName = icon.assetName {
            Image(assetName)
                .renderingMode(.template)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey?
    let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 6)
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(groupBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupBackground: Color {
        if colorScheme == .light {
            return Color(red: 236 / 255, green: 236 / 255, blue: 236 / 255)
        }

        return Color(red: 47 / 255, green: 47 / 255, blue: 49 / 255)
    }
}

private struct SettingsRow<Control: View>: View {
    private let controlColumnWidth: CGFloat = 252
    let title: LocalizedStringKey
    let description: LocalizedStringKey?
    let control: Control

    init(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))

                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            control
                .font(.system(size: 12))
                .frame(width: controlColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: description == nil ? 43 : 52)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}

private struct BackupPolicySummaryView: View {
    let language: EffectiveAppLanguage
    let latestBackupText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Viabar 自动保存各级备份")
                .font(.system(size: 13, weight: .semibold))
            Text("• 过去 24 小时每小时备份")
            Text("• 过去 7 天每天备份")
            Text("• 过去 6 个月每周备份")
            Text(AppLocalization.format("最新备份：%@", language: language, latestBackupText))
                .fontWeight(.semibold)
                .padding(.top, 5)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let schema = Schema([AppSettings.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    container.mainContext.insert(AppSettings())

    return SettingsView()
        .environment(ServiceContainer())
        .environment(AppRuntimeController())
        .modelContainer(container)
}
