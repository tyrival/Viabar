import AppKit
import SwiftData
import SwiftUI

struct MenuBarPanelView: View {
    @Query(sort: \Project.orderIndex) private var projects: [Project]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]

    @Environment(ServiceContainer.self) private var container
    @Environment(AppRuntimeController.self) private var runtimeController

    @State private var taskDraft = ""
    @State private var selectedProjectID: UUID?
    @State private var taskReminder: Reminder?
    @State private var showsReminderPopover = false
    @State private var projectPickerFlashIsBright = false

    private var projectService: ProjectService? {
        container.resolve(ProjectService.self)
    }

    private var settings: AppSettings? {
        settingsRecords.first
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settings?.language)
    }

    private var scope: MenuBarProjectScope {
        MenuBarProjectScope.resolve(settings?.menuBarProjectScope)
    }

    private var mode: MenuBarContentMode {
        MenuBarContentMode.resolve(settings?.menuBarContentMode)
    }

    private var cards: [MenuBarProjectCard] {
        MenuBarContentBuilder.cards(
            from: projects,
            scope: scope,
            mode: mode,
            now: Date()
        )
    }

    private var activeProjects: [Project] {
        projects.filter { !$0.isArchived }.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var draftHasText: Bool {
        !taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedProject: Project? {
        activeProjects.first { $0.projectId == selectedProjectID }
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: settings?.theme ?? "") ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var emptyTitle: LocalizedStringKey {
        mode == .currentTask ? "暂无当前任务" : "暂无今天需要处理的提醒"
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            content
            quickAdd
            footer
        }
        .padding(10)
        .frame(width: 390, height: 560)
        .background {
            ZStack {
                MenuBarPanelWindowConfigurator(
                    onPanelPresented: runtimeController.menuBarPanelDidPresent
                )
                Rectangle()
                    .fill(MenuBarPanelStyle.panelTint)
            }
        }
        .environment(\.locale, effectiveLanguage.locale)
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: selectedProjectID) { _, _ in
            projectPickerFlashIsBright = false
        }
        .onChange(of: draftHasText) { _, hasText in
            if !hasText {
                projectPickerFlashIsBright = false
            }
        }
    }

    private var header: some View {
        HStack {
            Menu {
                ForEach(MenuBarProjectScope.allCases) { choice in
                    Button {
                        menuBarProjectScopeBinding.wrappedValue = choice
                    } label: {
                        if choice == scope {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(scope.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MenuBarPanelStyle.headerTagForeground)
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(MenuBarPanelStyle.headerTagBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(MenuBarPanelStyle.headerTagBorder, lineWidth: 1.4)
                }
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if cards.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: mode == .currentTask ? "checkmark.circle" : "alarm")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(emptyTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(cards) { card in
                        MenuBarProjectCardView(
                            card: card,
                            settings: settings,
                            onOpenProject: { open(card.project, destination: .project) },
                            onOpenEntry: { open(card.project, destination: $0.destination) },
                            onToggleEntry: toggleEntry(_:)
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var quickAdd: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    TextField("添加任务", text: $taskDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .onSubmit(commitTask)
                }

                if draftHasText {
                    quickAddTags
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: draftHasText ? 64 : 36, alignment: .topLeading)
            .background(MenuBarPanelStyle.inputBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if draftHasText {
                Button(action: commitTask) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            selectedProject == nil
                                ? MenuBarPanelStyle.inactiveSubmitColor
                                : MenuBarPanelStyle.submitColor,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(Text(selectedProject == nil ? LocalizedStringKey("请选择项目") : LocalizedStringKey("添加任务")))
            }
        }
    }

    private var quickAddTags: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                projectPickerTag
                reminderTag
            }

            VStack(alignment: .leading, spacing: 7) {
                projectPickerTag
                reminderTag
            }
        }
    }

    private var projectPickerTag: some View {
        Menu {
            ForEach(activeProjects) { project in
                Button {
                    selectedProjectID = project.projectId
                } label: {
                    if selectedProjectID == project.projectId {
                        Label(project.title, systemImage: "checkmark")
                    } else {
                        Text(project.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedProject?.sfSymbolName ?? "folder")

                if let selectedProject {
                    Text(selectedProject.title)
                } else {
                    Text("选择项目")
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    projectPickerFlashIsBright
                        ? AnyShapeStyle(MenuBarPanelStyle.submitColor)
                        : projectPickerForeground
                )
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(
                    projectPickerFlashIsBright
                        ? MenuBarPanelStyle.reminderTagBackground
                        : MenuBarPanelStyle.inputTagBackground,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            projectPickerFlashIsBright ? MenuBarPanelStyle.submitColor : .clear,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var reminderTag: some View {
        Button {
            showsReminderPopover = true
        } label: {
            Label {
                if let taskReminder {
                    MenuBarReminderSummary(
                        reminder: taskReminder,
                        settings: settings,
                        language: effectiveLanguage
                    )
                } else {
                    Text("添加提醒")
                }
            } icon: {
                Image(systemName: taskReminder == nil ? "alarm" : "alarm.fill")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(taskReminder == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(MenuBarPanelStyle.submitColor))
            .padding(.horizontal, 9)
            .frame(height: 23)
            .background(
                (taskReminder == nil ? MenuBarPanelStyle.inputTagBackground : MenuBarPanelStyle.reminderTagBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsReminderPopover) {
            ReminderSettingsPopover(reminder: $taskReminder)
        }
    }

    private var projectPickerForeground: AnyShapeStyle {
        if let selectedProject {
            return AnyShapeStyle(Color(hex: selectedProject.accentColor))
        }
        return AnyShapeStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Spacer()

            Menu {
                Picker("项目", selection: menuBarProjectScopeBinding) {
                    ForEach(MenuBarProjectScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }

                Picker("功能", selection: menuBarContentModeBinding) {
                    ForEach(MenuBarContentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary.opacity(0.28), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .help("面板配置")
        }
    }

    private var menuBarProjectScopeBinding: Binding<MenuBarProjectScope> {
        Binding(
            get: { scope },
            set: {
                settings?.menuBarProjectScope = $0.rawValue
                projectService?.save()
            }
        )
    }

    private var menuBarContentModeBinding: Binding<MenuBarContentMode> {
        Binding(
            get: { mode },
            set: {
                settings?.menuBarContentMode = $0.rawValue
                projectService?.save()
            }
        )
    }

    private func open(_ project: Project, destination: GlobalSearchDestination) {
        runtimeController.navigate(
            to: GlobalSearchNavigationRequest(projectID: project.projectId, destination: destination)
        )
    }

    private func toggleEntry(_ entry: MenuBarTaskEntry) {
        switch entry.destination {
        case let .milestone(id):
            if let milestone = projects.flatMap(\.milestones).first(where: { $0.milestoneId == id }) {
                projectService?.toggleMilestoneComplete(milestone)
            }
        case let .subTask(_, id):
            if let subTask = projects.flatMap(\.milestones).flatMap(\.subtasks).first(where: { $0.taskId == id }) {
                projectService?.toggleSubTaskComplete(subTask)
            }
        default:
            break
        }
    }

    private func commitTask() {
        let title = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let selectedProject else {
            projectPickerFlashIsBright = false
            withAnimation(.easeInOut(duration: 0.32).repeatCount(6, autoreverses: true)) {
                projectPickerFlashIsBright = true
            }
            return
        }
        let milestone = projectService?.addMilestone(to: selectedProject, title: title)
        if let milestone, let taskReminder {
            projectService?.updateReminder(taskReminder, for: milestone)
        }
        taskDraft = ""
        selectedProjectID = nil
        taskReminder = nil
        projectPickerFlashIsBright = false
        showsReminderPopover = false
    }
}

private struct MenuBarProjectCardView: View {
    let card: MenuBarProjectCard
    let settings: AppSettings?
    let onOpenProject: () -> Void
    let onOpenEntry: (MenuBarTaskEntry) -> Void
    let onToggleEntry: (MenuBarTaskEntry) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredText: HoveredText?

    private enum HoveredText: Equatable {
        case project
        case entry(String)
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settings?.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onOpenProject) {
                HStack(spacing: 7) {
                    Image(systemName: card.project.sfSymbolName)
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                    Text(card.project.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            (colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                                .opacity(hoveredText == .project ? 0.72 : 1)
                        )
                    Spacer()
                    if card.project.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(MenuBarPanelStyle.favoriteColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { hoveredText = $0 ? .project : nil }

            ForEach(card.entries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        onToggleEntry(entry)
                    } label: {
                        Image(systemName: "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(MenuBarPanelStyle.checkboxColor)
                    }
                    .buttonStyle(.plain)

                    MenuBarTaskMarkerDot(markerColor: entry.markerColor)
                        .padding(.top, 5)

                    Button {
                        onOpenEntry(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(entry.title)
                                    .lineLimit(2)
                                    .opacity(hoveredText == .entry(entry.id) ? 0.72 : 1)
                                if entry.source == .projectReminder {
                                    Text("项目提醒")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.callout)
                            .foregroundStyle(.primary)

                            if let parentTitle = entry.parentTitle {
                                Text(parentTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .opacity(hoveredText == .entry(entry.id) ? 0.72 : 1)
                            }

                            if let reminder = entry.reminder {
                                MenuBarReminderSummary(
                                    reminder: reminder,
                                    settings: settings,
                                    language: effectiveLanguage
                                )
                                .font(.caption)
                                .foregroundStyle(reminder.isOverdue(at: Date()) ? .red : .orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .onHover {
                        hoveredText = $0 ? .entry(entry.id) : nil
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MenuBarPanelStyle.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MenuBarPanelStyle.cardBorder, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: hoveredText)
    }
}

private struct MenuBarTaskMarkerDot: View {
    let markerColor: TaskMarkerColor?

    var body: some View {
        if let markerColor {
            Circle()
                .fill(ViabarColor.taskMarker(markerColor))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }
}

private struct MenuBarReminderSummary: View {
    let reminder: Reminder
    let settings: AppSettings?
    let language: EffectiveAppLanguage

    var body: some View {
        HStack(spacing: 5) {
            if let fireDate = reminder.displayFireDate {
                Text(AppDateFormatter.string(from: fireDate, pattern: settings?.dateFormat))
            } else {
                Text("--")
            }

            if reminder.isRepeating {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .semibold))
                Text(reminder.repeatTitle(language: language))
            }
        }
    }
}

private struct MenuBarPanelWindowConfigurator: NSViewRepresentable {
    let onPanelPresented: () -> Void

    func makeNSView(context: Context) -> MenuBarPanelProbeView {
        let view = MenuBarPanelProbeView()
        view.onWindowResolved = applyWindowAppearance
        return view
    }

    func updateNSView(_ nsView: MenuBarPanelProbeView, context: Context) {
        nsView.onWindowResolved = applyWindowAppearance
        nsView.resolveCurrentWindow()
    }

    private func applyWindowAppearance(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        onPanelPresented()
    }
}

private final class MenuBarPanelProbeView: NSView {
    var onWindowResolved: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveCurrentWindow()
    }

    func resolveCurrentWindow() {
        guard let window else { return }
        onWindowResolved?(window)
    }
}

struct MenuBarStatusLabelView: View {
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

private enum MenuBarPanelStyle {
    static let panelTint = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 0.36)
            : NSColor(calibratedRed: 0.78, green: 0.87, blue: 0.97, alpha: 0.02)
    })
    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.54)
            : NSColor(calibratedWhite: 0.97, alpha: 0.32)
    })
    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.52, alpha: 0.36)
            : NSColor(calibratedWhite: 0.70, alpha: 0.52)
    })
    static let headerTagForeground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.92, alpha: 1)
            : NSColor(calibratedWhite: 0.28, alpha: 1)
    })
    static let headerTagBackground = Color(nsColor: .controlBackgroundColor).opacity(0.42)
    static let headerTagBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.12, green: 0.83, blue: 0.96, alpha: 1)
            : NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.85, alpha: 1)
    })
    static let inputBackground = Color(nsColor: .controlBackgroundColor).opacity(0.70)
    static let inputTagBackground = Color(nsColor: .separatorColor).opacity(0.16)
    static let checkboxColor = Color(nsColor: .secondaryLabelColor)
    static let favoriteColor = Color(nsColor: .systemYellow)
    static let submitColor = Color(nsColor: .systemOrange)
    static let inactiveSubmitColor = Color(nsColor: .tertiaryLabelColor).opacity(0.55)
    static let reminderTagBackground = Color(nsColor: .systemOrange).opacity(0.16)
}
