import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case overview
    case project(Project)
}

enum FolderNamePrompt: Identifiable {
    case createRoot
    case createChild(ArchiveFolder)
    case rename(ArchiveFolder)

    var id: String {
        switch self {
        case .createRoot:
            return "create-root"
        case .createChild(let folder):
            return "create-child-\(folder.folderId.uuidString)"
        case .rename(let folder):
            return "rename-\(folder.folderId.uuidString)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .createRoot:
            return "新建文件夹"
        case .createChild:
            return "新建子文件夹"
        case .rename:
            return "重命名文件夹"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .createRoot:
            return "输入归档文件夹名称。"
        case .createChild(let folder):
            return "在“\(folder.name)”下创建子文件夹。"
        case .rename:
            return "输入新的文件夹名称。"
        }
    }

    var confirmTitle: LocalizedStringKey {
        switch self {
        case .rename:
            return "重命名"
        default:
            return "创建"
        }
    }
}

enum DeleteConfirmation: Identifiable {
    case nonEmptyFolder(ArchiveFolder)

    var id: String {
        switch self {
        case .nonEmptyFolder(let folder):
            return "folder-\(folder.folderId.uuidString)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .nonEmptyFolder:
            return "删除文件夹？"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .nonEmptyFolder(let folder):
            return "“\(folder.name)”不是空文件夹，删除后其中的项目和子文件夹均不可恢复。"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Environment(ServiceContainer.self) private var container
    @Query(sort: \Project.orderIndex) private var allProjects: [Project]
    @Query(sort: \ArchiveFolder.orderIndex) private var allFolders: [ArchiveFolder]
    @Binding var selection: SidebarSelection?
    var revealRequest: GlobalSearchNavigationRequest? = nil

    @State private var showNewProjectSheet: Bool = false
    @State private var showTemplateSheet: Bool = false
    @State private var editingProject: Project?
    @State private var isArchiveExpanded: Bool = false
    @State private var archivePickerProject: Project?
    @State private var expandedFolderIds: Set<UUID> = []
    @State private var draggingActiveProjectId: UUID?
    @State private var activeProjectDropTarget: ActiveProjectDropTarget?
    @State private var draggingArchiveFolderId: UUID?
    @State private var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @State private var archiveProjectDropTargetFolderId: UUID?
    @State private var archiveProjectDropTarget: ArchiveProjectDropTarget?
    @State private var folderNamePrompt: FolderNamePrompt?
    @State private var folderNameDraft: String = ""
    @State private var deleteConfirmation: DeleteConfirmation?
    @State private var projectPendingDeletion: Project?
    @State private var isTrashBrowserPresented = false
    @State private var isTrashHovered = false
    @State private var isOverviewHovered = false
    @State private var isCreateProjectButtonHovered = false
    @State private var isTemplateButtonHovered = false
    @State private var isCreateArchiveFolderButtonHovered = false

    private var projectService: ProjectService? {
        container.projectService
    }

    private var activeProjects: [Project] {
        allProjects.filter { !$0.isArchived }
    }

    private var rootFolders: [ArchiveFolder] {
        allFolders.filter { $0.parent == nil }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                overviewSection
                projectsSection
                archiveSection
            }
            .listStyle(.sidebar)

            Button {
                isTrashBrowserPresented = true
            } label: {
                Label("回收站", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: ActiveProjectRowMetrics.defaultRowHeight)
                    .background {
                        Capsule(style: .continuous)
                            .fill(isTrashHovered ? ActiveProjectRowMetrics.sidebarHoverColor : .clear)
                    }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ActiveProjectRowMetrics.defaultHorizontalInset)
            .padding(.bottom, 8)
            .onHover { isTrashHovered = $0 }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectView()
        }
        .sheet(isPresented: $showTemplateSheet) {
            ProjectTemplateManagementView()
        }
        .sheet(item: $editingProject) { project in
            NewProjectView(editingProject: project)
        }
        .sheet(isPresented: $isTrashBrowserPresented) {
            TrashBrowserView()
                .presentationSizing(.fitted)
        }
        .alert(
            folderNamePrompt?.title ?? "",
            isPresented: Binding(
                get: { folderNamePrompt != nil },
                set: { if !$0 { dismissFolderNamePrompt() } }
            )
        ) {
            TextField("文件夹名", text: $folderNameDraft)
            Button(folderNamePrompt?.confirmTitle ?? "确定") {
                commitFolderNamePrompt()
            }
            Button("取消", role: .cancel) {
                dismissFolderNamePrompt()
            }
        } message: {
            Text(folderNamePrompt?.message ?? "")
        }
        .alert(
            deleteConfirmation?.title ?? "",
            isPresented: Binding(
                get: { deleteConfirmation != nil },
                set: { if !$0 { deleteConfirmation = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                commitDeleteConfirmation()
            }
            Button("取消", role: .cancel) {
                deleteConfirmation = nil
            }
        } message: {
            Text(deleteConfirmation?.message ?? "")
        }
        .permanentProjectDeletionConfirmation(project: $projectPendingDeletion) { project in
            if selection == .project(project) {
                selection = .overview
            }
            projectService?.deleteProject(project)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .onAppear {
            revealArchivedProject(revealRequest?.projectID)
        }
        .onChange(of: revealRequest?.id) { _, _ in
            revealArchivedProject(revealRequest?.projectID)
        }
        .archiveFolderPicker(
            isPresented: Binding(
                get: { archivePickerProject != nil },
                set: { if !$0 { archivePickerProject = nil } }
            ),
            project: archivePickerProject ?? Project(title: ""),
            onConfirm: { folder in
                guard let project = archivePickerProject else { return }
                projectService?.archiveProject(project, to: folder)
                archivePickerProject = nil
            }
        )
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            let isOverviewSelected = selection == .overview
            let overviewProgressBarHeight = isOverviewSelected
                ? ActiveProjectRowMetrics.selectedProgressBarHeight
                : ActiveProjectRowMetrics.defaultProgressBarHeight
            let overviewRowHeight = isOverviewSelected
                ? ActiveProjectRowMetrics.selectedRowHeight
                : ActiveProjectRowMetrics.defaultRowHeight
            let overviewHorizontalInset = isOverviewSelected
                ? ActiveProjectRowMetrics.selectedHorizontalInset
                : ActiveProjectRowMetrics.defaultHorizontalInset

            Button {
                selection = .overview
            } label: {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            isOverviewSelected
                                ? ViabarColor.primary
                                : isOverviewHovered
                                    ? ActiveProjectRowMetrics.sidebarHoverColor
                                    : ActiveProjectRowMetrics.progressTrackColor
                        )
                        .frame(height: overviewProgressBarHeight)

                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title3)
                        Text("总览")
                            .font(ActiveProjectRowMetrics.projectTitleFont)
                        Spacer()
                    }
                    .foregroundStyle(isOverviewSelected ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .frame(height: overviewRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, overviewHorizontalInset)
                .padding(.vertical, isOverviewSelected ? ActiveProjectRowMetrics.selectedShadowBleed : 0)
                .offset(y: isOverviewSelected ? ActiveProjectRowMetrics.selectedLift : 0)
                .contentShape(Capsule(style: .continuous))
                .animation(ActiveProjectRowMetrics.selectionAnimation, value: isOverviewSelected)
            }
            .buttonStyle(.plain)
            .onHover { isOverviewHovered = $0 }
        }
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        Section {
            if activeProjects.isEmpty {
                EmptyHintView(
                    icon: "tray",
                    message: "暂无项目",
                    action: "新建项目",
                    onAction: { showNewProjectSheet = true }
                )
            } else {
                ForEach(Array(activeProjects.enumerated()), id: \.element.projectId) { index, project in
                    if index == 0 {
                        ActiveProjectReorderSeparator(
                            isActive: activeProjectDropTarget == ActiveProjectDropTarget(projectId: project.projectId, placement: .before)
                        )
                        .onDrop(
                            of: [.plainText],
                            delegate: ActiveProjectBoundaryDropDelegate(
                                targetProject: project,
                                placement: .before,
                                activeProjects: activeProjects,
                                service: projectService,
                                draggingProjectId: $draggingActiveProjectId,
                                dropTarget: $activeProjectDropTarget
                            )
                        )
                    }

                    ActiveProjectRow(
                        project: project,
                        isSelected: selection == .project(project),
                        highlightRequestID: projectHighlightRequestID(for: project),
                        onEdit: { editingProject = project },
                        onArchive: { archivePickerProject = project },
                        onDelete: { showDeleteProjectConfirmation(project) },
                        onSelect: {
                            selection = .project(project)
                        }
                    )
                    .onDrag {
                        draggingActiveProjectId = project.projectId
                        let provider = NSItemProvider(object: project.projectId.uuidString as NSString)
                        return provider
                    }

                    ActiveProjectReorderSeparator(
                        isActive: activeProjectDropTarget == ActiveProjectDropTarget(projectId: project.projectId, placement: .after)
                    )
                    .onDrop(
                        of: [.plainText],
                        delegate: ActiveProjectBoundaryDropDelegate(
                            targetProject: project,
                            placement: .after,
                            activeProjects: activeProjects,
                            service: projectService,
                            draggingProjectId: $draggingActiveProjectId,
                            dropTarget: $activeProjectDropTarget
                        )
                    )
                }
                .onMove { offsets, target in
                    projectService?.reorderActiveProjects(fromOffsets: offsets, toOffset: target)
                }
            }
        } header: {
            HStack {
                Text("项目")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showNewProjectSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(isCreateProjectButtonHovered ? AnyShapeStyle(ViabarColor.primaryLight) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help("新建项目")
                .onHover { isCreateProjectButtonHovered = $0 }
                Button {
                    showTemplateSheet = true
                } label: {
                    Image(systemName: "square.3.layers.3d.middle.filled")
                        .font(.system(size: 14))
                        .foregroundStyle(isTemplateButtonHovered ? AnyShapeStyle(ViabarColor.primaryLight) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("模板管理")
                .onHover { isTemplateButtonHovered = $0 }
            }
        }
    }

    // MARK: - Archive Section

    private var archiveSection: some View {
        Section {
            if isArchiveExpanded {
                archiveContent
            }
        } header: {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isArchiveExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("归档")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isArchiveExpanded.toggle()
                    }
                }

                Spacer()

                Button {
                    showCreateRootFolderPrompt()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.title3)
                        .foregroundStyle(isCreateArchiveFolderButtonHovered ? AnyShapeStyle(ViabarColor.primaryLight) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("新建文件夹")
                .onHover { isCreateArchiveFolderButtonHovered = $0 }
            }
        }
    }

    @ViewBuilder
    private var archiveContent: some View {
        if rootFolders.isEmpty {
            EmptyHintView(
                icon: "archivebox",
                message: "暂无归档文件夹",
                action: "创建文件夹",
                onAction: { showCreateRootFolderPrompt() }
            )
        } else {
            ForEach(rootFolders) { folder in
                RecursiveFolderRow(
                    folder: folder,
                    selection: $selection,
                    level: 0,
                    projectHighlightRequest: revealRequest,
                    expandedFolderIds: $expandedFolderIds,
                    draggingActiveProjectId: $draggingActiveProjectId,
                    activeProjectDropTarget: $activeProjectDropTarget,
                    draggingArchiveFolderId: $draggingArchiveFolderId,
                    archiveFolderDropTarget: $archiveFolderDropTarget,
                    archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                    archiveProjectDropTarget: $archiveProjectDropTarget,
                    allProjects: allProjects,
                    allFolders: allFolders,
                    service: projectService,
                    onCreateSubfolder: showCreateSubfolderPrompt,
                    onRenameFolder: showRenameFolderPrompt,
                    onDeleteFolder: requestDeleteFolder,
                    onDeleteProject: showDeleteProjectConfirmation
                )
            }
            .onMove { offsets, target in
                projectService?.reorderFolders(fromOffsets: offsets, toOffset: target)
            }
        }
    }

    private func showCreateRootFolderPrompt() {
        folderNameDraft = ""
        folderNamePrompt = .createRoot
    }

    private func showCreateSubfolderPrompt(parent: ArchiveFolder) {
        folderNameDraft = ""
        folderNamePrompt = .createChild(parent)
    }

    private func showRenameFolderPrompt(folder: ArchiveFolder) {
        folderNameDraft = folder.name
        folderNamePrompt = .rename(folder)
    }

    private func dismissFolderNamePrompt() {
        folderNamePrompt = nil
        folderNameDraft = ""
    }

    private func commitFolderNamePrompt() {
        guard let prompt = folderNamePrompt else { return }
        let name = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            dismissFolderNamePrompt()
            return
        }

        switch prompt {
        case .createRoot:
            projectService?.createArchiveFolder(name: name)
            withAnimation(.easeInOut(duration: 0.15)) {
                isArchiveExpanded = true
            }
        case .createChild(let parent):
            projectService?.createArchiveFolder(name: name, parent: parent)
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedFolderIds.insert(parent.folderId)
            }
        case .rename(let folder):
            folder.name = name
            projectService?.save()
        }

        dismissFolderNamePrompt()
    }

    private func showDeleteProjectConfirmation(_ project: Project) {
        projectPendingDeletion = project
    }

    private func requestDeleteFolder(_ folder: ArchiveFolder) {
        if folder.children.isEmpty && folder.projects.isEmpty {
            projectService?.deleteArchiveFolder(folder)
        } else {
            deleteConfirmation = .nonEmptyFolder(folder)
        }
    }

    private func commitDeleteConfirmation() {
        guard let confirmation = deleteConfirmation else { return }

        switch confirmation {
        case .nonEmptyFolder(let folder):
            projectService?.deleteArchiveFolder(folder)
        }

        deleteConfirmation = nil
    }

    private func revealArchivedProject(_ projectID: UUID?) {
        guard let projectID,
              let project = allProjects.first(where: { $0.projectId == projectID && $0.isArchived }),
              let folder = project.archiveFolder
        else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            isArchiveExpanded = true
            var current: ArchiveFolder? = folder
            while let currentFolder = current {
                expandedFolderIds.insert(currentFolder.folderId)
                current = currentFolder.parent
            }
        }
    }

    private func projectHighlightRequestID(for project: Project) -> UUID? {
        guard revealRequest?.projectID == project.projectId,
              case .some(.project) = revealRequest?.destination
        else { return nil }
        return revealRequest?.id
    }

}

// MARK: - ActiveProjectRow

private enum ActiveProjectRowMetrics {
    static let defaultProgressBarHeight: CGFloat = 32
    static let selectedProgressBarHeight: CGFloat = 36
    static let defaultRowHeight: CGFloat = 32
    static let selectedRowHeight: CGFloat = 36
    static let defaultHorizontalInset: CGFloat = 6
    static let selectedHorizontalInset: CGFloat = 0
    static let progressTrackColor = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.74)
            : NSColor(calibratedWhite: 0.92, alpha: 1)
    })
    static let sidebarHoverColor = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.32, alpha: 0.55)
            : NSColor(calibratedWhite: 0.82, alpha: 0.82)
    })
    static let progressPercentColor = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.68, alpha: 1)
            : NSColor(calibratedWhite: 0.42, alpha: 1)
    })
    /// 项目未选中时的进度条填充色（浅色/深色模式在此处调整）
    static let progressUnselectedFillColor = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.30, alpha: 0.88)
            : NSColor(calibratedWhite: 0.78, alpha: 0.6)
    })
    static let defaultShadowOpacity: Double = 0.035
    static let defaultShadowRadius: CGFloat = 2
    static let defaultShadowYOffset: CGFloat = 1
    static let selectedFarShadowOpacity: Double = 0.07
    static let selectedFarShadowRadius: CGFloat = 3
    static let selectedFarShadowYOffset: CGFloat = 6
    static let selectedNearShadowOpacity: Double = 0.04
    static let selectedNearShadowRadius: CGFloat = 1
    static let selectedNearShadowYOffset: CGFloat = 3
    static let selectedShadowInset: CGFloat = 5
    static let selectedShadowBleed: CGFloat = 2
    static let selectedLift: CGFloat = 0
    static let projectTitleFont = Font.callout
    static let shadowAnimationDuration: Double = 0.15
    static let shadowAnimation = Animation.easeInOut(duration: shadowAnimationDuration)
    static let selectionAnimation = Animation.easeInOut(duration: shadowAnimationDuration)
}

struct ActiveProjectRow: View {
    let project: Project
    let isSelected: Bool
    var highlightRequestID: UUID? = nil
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Environment(ServiceContainer.self) private var container
    @State private var isHovered = false

    private var projectService: ProjectService? {
        container.projectService
    }

    /// 填充色：100% → success，否则 → 项目自定义主题色
    private var accentColor: Color {
        project.progress >= 1.0
            ? ViabarColor.success
            : Color(hex: project.accentColor)
    }

    private var progressBarHeight: CGFloat {
        isSelected ? ActiveProjectRowMetrics.selectedProgressBarHeight : ActiveProjectRowMetrics.defaultProgressBarHeight
    }

    private var rowHeight: CGFloat {
        isSelected ? ActiveProjectRowMetrics.selectedRowHeight : ActiveProjectRowMetrics.defaultRowHeight
    }

    private var horizontalInset: CGFloat {
        isSelected ? ActiveProjectRowMetrics.selectedHorizontalInset : ActiveProjectRowMetrics.defaultHorizontalInset
    }

    private var hasScheduledProjectReminder: Bool {
        project.reminder != nil && !project.isArchived && project.topUnfinishedTitle != nil
    }

    private func shadowCapsule(color: Color = .black, opacity: Double, radius: CGFloat, yOffset: CGFloat, inset: CGFloat = 0) -> some View {
        Capsule(style: .continuous)
            .fill(color.opacity(opacity))
            .frame(height: progressBarHeight)
            .padding(.horizontal, inset)
            .offset(y: yOffset)
            .blur(radius: radius)
            .allowsHitTesting(false)
    }

    /// 公共内容行，供双层渲染复用
    private func rowContent(
        color: Color,
        usesProjectIconColor: Bool = false,
        usesMutedPercentColor: Bool = false,
        usesProjectReminderColor: Bool = false,
        usesFixedFavoriteColor: Bool = false
    ) -> some View {
        let percentColor = usesMutedPercentColor ? ActiveProjectRowMetrics.progressPercentColor : color
        let reminderColor = usesProjectReminderColor ? Color.orange : color
        let favoriteColor = usesFixedFavoriteColor ? ViabarColor.warning : Color.clear

        return HStack(spacing: 0) {
            Image(systemName: project.sfSymbolName)
                .font(.title3)
                .foregroundStyle(usesProjectIconColor ? accentColor : color)
                .padding(.trailing, 6)
            Text(project.title)
                .font(ActiveProjectRowMetrics.projectTitleFont)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 2)
            HStack(spacing: 2) {
                if hasScheduledProjectReminder {
                    Image(systemName: "alarm.fill")
                        .font(.caption)
                        .foregroundStyle(reminderColor)
                        .frame(width: 14)
                }
                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(favoriteColor)
                        .frame(width: 14)
                }
                Text("\(Int(project.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(percentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    var body: some View {
        ZStack(alignment: .center) {
            Group {
                shadowCapsule(
                    opacity: isSelected ? ActiveProjectRowMetrics.selectedFarShadowOpacity : 0,
                    radius: ActiveProjectRowMetrics.selectedFarShadowRadius,
                    yOffset: ActiveProjectRowMetrics.selectedFarShadowYOffset,
                    inset: ActiveProjectRowMetrics.selectedShadowInset
                )
                shadowCapsule(
                    opacity: isSelected ? ActiveProjectRowMetrics.selectedNearShadowOpacity : 0,
                    radius: ActiveProjectRowMetrics.selectedNearShadowRadius,
                    yOffset: ActiveProjectRowMetrics.selectedNearShadowYOffset,
                    inset: ActiveProjectRowMetrics.selectedShadowInset
                )
                shadowCapsule(
                    opacity: isSelected ? 0 : ActiveProjectRowMetrics.defaultShadowOpacity,
                    radius: ActiveProjectRowMetrics.defaultShadowRadius,
                    yOffset: ActiveProjectRowMetrics.defaultShadowYOffset
                )
            }
            .animation(ActiveProjectRowMetrics.shadowAnimation, value: isSelected)

            // 轨道底色
            Capsule(style: .continuous)
                .fill(
                    !isSelected && isHovered
                        ? ActiveProjectRowMetrics.sidebarHoverColor
                        : ActiveProjectRowMetrics.progressTrackColor
                )
                .frame(height: progressBarHeight)

            // 进度填充
            GeometryReader { geo in
                Capsule(style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.88) : ActiveProjectRowMetrics.progressUnselectedFillColor)
                    .frame(
                        width: max(0, min(geo.size.width, geo.size.width * CGFloat(project.progress))),
                        height: progressBarHeight
                    )
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            // 深色文字层
            rowContent(
                color: .primary,
                usesProjectIconColor: true,
                usesMutedPercentColor: true,
                usesProjectReminderColor: true,
                usesFixedFavoriteColor: true
            )

            // 白色文字层（仅选中时显示，产生反色效果）
            if isSelected {
                GeometryReader { geo in
                    let fillW = geo.size.width * CGFloat(project.progress)
                    rowContent(color: .white)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                        .mask(
                            HStack(spacing: 0) {
                                Color.white.frame(width: fillW)
                                Color.clear
                            }
                        )
                }
            }
        }
        .frame(height: rowHeight)
        .padding(.horizontal, horizontalInset)
        .searchTargetHighlight(
            triggerID: highlightRequestID,
            isActive: highlightRequestID != nil,
            cornerRadius: rowHeight / 2
        )
        .padding(.vertical, isSelected ? ActiveProjectRowMetrics.selectedShadowBleed : 0)
        .offset(y: isSelected ? ActiveProjectRowMetrics.selectedLift : 0)
        .animation(ActiveProjectRowMetrics.selectionAnimation, value: isSelected)
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button { onEdit() } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button { onArchive() } label: {
                Label("归档", systemImage: "archivebox")
            }
            Button {
                projectService?.toggleFavorite(project)
            } label: {
                if project.isFavorite {
                    Label("取消收藏", systemImage: "star.slash")
                } else {
                    Label("收藏", systemImage: "star")
                }
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

}

// MARK: - Active Project Reorder

struct ActiveProjectDropTarget: Equatable {
    let projectId: UUID
    let placement: ActiveProjectDropPlacement
}

enum ActiveProjectDropPlacement: Equatable {
    case before
    case after
}

struct ActiveProjectDropIndicator: View {
    var body: some View {
        Rectangle()
            .fill(.blue)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .shadow(color: .blue.opacity(0.45), radius: 2)
            .allowsHitTesting(false)
    }
}

struct ActiveProjectReorderSeparator: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.primary.opacity(0.001)
            if isActive {
                ActiveProjectDropIndicator()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
        .contentShape(Rectangle())
    }
}

struct ActiveProjectBoundaryDropDelegate: DropDelegate {
    let targetProject: Project
    let placement: ActiveProjectDropPlacement
    let activeProjects: [Project]
    weak var service: ProjectService?
    @Binding var draggingProjectId: UUID?
    @Binding var dropTarget: ActiveProjectDropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]),
              let draggingProjectId
        else { return false }
        return draggingProjectId != targetProject.projectId
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.projectId == targetProject.projectId,
           dropTarget?.placement == placement {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingProjectId = nil
            dropTarget = nil
        }

        guard let service,
              let draggingProjectId,
              let sourceIndex = activeProjects.firstIndex(where: { $0.projectId == draggingProjectId }),
              let targetIndex = activeProjects.firstIndex(where: { $0.projectId == targetProject.projectId }),
              sourceIndex != targetIndex
        else { return false }

        let destination = targetIndex + (placement == .after ? 1 : 0)
        guard sourceIndex != destination else { return false }

        service.reorderActiveProjects(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        return true
    }

    private func updateDropTarget() {
        guard let draggingProjectId, draggingProjectId != targetProject.projectId else {
            dropTarget = nil
            return
        }
        dropTarget = ActiveProjectDropTarget(projectId: targetProject.projectId, placement: placement)
    }
}

// MARK: - Archive Folder Drag

struct ArchiveFolderDropTarget: Equatable {
    let folderId: UUID
    let placement: ArchiveFolderDropPlacement
}

enum ArchiveFolderDropPlacement: Equatable {
    case before
    case into
    case after
}

struct ArchiveFolderDropIndicator: View {
    var body: some View {
        Rectangle()
            .fill(.blue)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .shadow(color: .blue.opacity(0.45), radius: 2)
            .allowsHitTesting(false)
    }
}

// MARK: - Archive Project Reorder

struct ArchiveProjectDropTarget: Equatable {
    let projectId: UUID
    let placement: ActiveProjectDropPlacement
}

struct ArchiveProjectBoundaryDropDelegate: DropDelegate {
    let targetProject: Project
    let placement: ActiveProjectDropPlacement
    let folder: ArchiveFolder
    let folderProjects: [Project]
    weak var service: ProjectService?
    @Binding var draggingProjectId: UUID?
    @Binding var dropTarget: ArchiveProjectDropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]),
              let draggingProjectId
        else { return false }
        return draggingProjectId != targetProject.projectId
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.projectId == targetProject.projectId,
           dropTarget?.placement == placement {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingProjectId = nil
            dropTarget = nil
        }

        guard let service,
              let draggingProjectId,
              let sourceIndex = folderProjects.firstIndex(where: { $0.projectId == draggingProjectId }),
              let targetIndex = folderProjects.firstIndex(where: { $0.projectId == targetProject.projectId }),
              sourceIndex != targetIndex
        else { return false }

        let destination = moveDestination(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            placement: placement
        )
        guard sourceIndex != destination else { return false }

        service.reorderFolderProjects(folder, fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        return true
    }

    private func updateDropTarget() {
        guard let draggingProjectId, draggingProjectId != targetProject.projectId else {
            dropTarget = nil
            return
        }
        dropTarget = ArchiveProjectDropTarget(projectId: targetProject.projectId, placement: placement)
    }

    private func moveDestination(
        sourceIndex: Int,
        targetIndex: Int,
        placement: ActiveProjectDropPlacement
    ) -> Int {
        switch placement {
        case .before:
            return sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        case .after:
            return sourceIndex < targetIndex ? targetIndex : targetIndex + 1
        }
    }
}

// MARK: - RecursiveFolderRow

/// 递归文件夹行 —— 支持无限嵌套级连目录树。
/// 每一层都是独立的 List 行，自带展开/折叠、拖放接收、项目列表。
struct RecursiveFolderRow: View {
    let folder: ArchiveFolder
    @Binding var selection: SidebarSelection?
    let level: Int
    let projectHighlightRequest: GlobalSearchNavigationRequest?
    @Binding var expandedFolderIds: Set<UUID>
    @Binding var draggingActiveProjectId: UUID?
    @Binding var activeProjectDropTarget: ActiveProjectDropTarget?
    @Binding var draggingArchiveFolderId: UUID?
    @Binding var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @Binding var archiveProjectDropTargetFolderId: UUID?
    @Binding var archiveProjectDropTarget: ArchiveProjectDropTarget?
    let allProjects: [Project]
    let allFolders: [ArchiveFolder]
    weak var service: ProjectService?
    let onCreateSubfolder: (ArchiveFolder) -> Void
    let onRenameFolder: (ArchiveFolder) -> Void
    let onDeleteFolder: (ArchiveFolder) -> Void
    let onDeleteProject: (Project) -> Void

    private var isExpanded: Bool {
        expandedFolderIds.contains(folder.folderId)
    }

    private var sortedProjects: [Project] {
        folder.projects.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var sortedChildren: [ArchiveFolder] {
        folder.children.sorted { $0.orderIndex < $1.orderIndex }
    }

    private let indentPerLevel: CGFloat = 16

    private func projectHighlightRequestID(for project: Project) -> UUID? {
        guard projectHighlightRequest?.projectID == project.projectId,
              case .some(.project) = projectHighlightRequest?.destination
        else { return nil }
        return projectHighlightRequest?.id
    }

    var body: some View {
        // 文件夹头部 + 展开内容包装，不套多余 VStack
        // 让 List 能识别内部 ForEach 生产的行
        FolderHeaderRow(
            folder: folder,
            isExpanded: isExpanded,
            level: level,
            onTap: {
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isExpanded {
                        expandedFolderIds.remove(folder.folderId)
                    } else {
                        expandedFolderIds.insert(folder.folderId)
                    }
                }
            },
            service: service,
            allProjects: allProjects,
            allFolders: allFolders,
            expandedFolderIds: $expandedFolderIds,
            draggingActiveProjectId: $draggingActiveProjectId,
            activeProjectDropTarget: $activeProjectDropTarget,
            draggingArchiveFolderId: $draggingArchiveFolderId,
            archiveFolderDropTarget: $archiveFolderDropTarget,
            archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
            onCreateSubfolder: onCreateSubfolder,
            onRenameFolder: onRenameFolder,
            onDeleteFolder: onDeleteFolder
        )

        if isExpanded {
            // 子文件夹（递归）
            ForEach(sortedChildren) { child in
                RecursiveFolderRow(
                    folder: child,
                    selection: $selection,
                    level: level + 1,
                    projectHighlightRequest: projectHighlightRequest,
                    expandedFolderIds: $expandedFolderIds,
                    draggingActiveProjectId: $draggingActiveProjectId,
                    activeProjectDropTarget: $activeProjectDropTarget,
                    draggingArchiveFolderId: $draggingArchiveFolderId,
                    archiveFolderDropTarget: $archiveFolderDropTarget,
                    archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                    archiveProjectDropTarget: $archiveProjectDropTarget,
                    allProjects: allProjects,
                    allFolders: allFolders,
                    service: service,
                    onCreateSubfolder: onCreateSubfolder,
                    onRenameFolder: onRenameFolder,
                    onDeleteFolder: onDeleteFolder,
                    onDeleteProject: onDeleteProject
                )
            }

            // 项目列表
            if sortedProjects.isEmpty {
                EmptyView()
            } else {
                ForEach(Array(sortedProjects.enumerated()), id: \.element.projectId) { index, project in
                    if index == 0 {
                        ActiveProjectReorderSeparator(
                            isActive: archiveProjectDropTarget == ArchiveProjectDropTarget(projectId: project.projectId, placement: .before)
                        )
                        .onDrop(
                            of: [.plainText],
                            delegate: ArchiveProjectBoundaryDropDelegate(
                                targetProject: project,
                                placement: .before,
                                folder: folder,
                                folderProjects: sortedProjects,
                                service: service,
                                draggingProjectId: $draggingActiveProjectId,
                                dropTarget: $archiveProjectDropTarget
                            )
                        )
                    }

                    ArchivedProjectSelectableRow(
                        project: project,
                        level: level,
                        indentPerLevel: indentPerLevel,
                        isSelected: selection == .project(project),
                        highlightRequestID: projectHighlightRequestID(for: project),
                        onDragStart: { draggingActiveProjectId = project.projectId },
                        onDelete: { onDeleteProject(project) }
                    ) {
                        selection = .project(project)
                    }

                    ActiveProjectReorderSeparator(
                        isActive: archiveProjectDropTarget == ArchiveProjectDropTarget(projectId: project.projectId, placement: .after)
                    )
                    .onDrop(
                        of: [.plainText],
                        delegate: ArchiveProjectBoundaryDropDelegate(
                            targetProject: project,
                            placement: .after,
                            folder: folder,
                            folderProjects: sortedProjects,
                            service: service,
                            draggingProjectId: $draggingActiveProjectId,
                            dropTarget: $archiveProjectDropTarget
                        )
                    )
                }
                .onMove { offsets, target in
                    service?.reorderFolderProjects(folder, fromOffsets: offsets, toOffset: target)
                }
            }
        }
    }
}

// MARK: - FolderHeaderRow

/// 文件夹头部行 —— 自带 .onDrop 接收拖入的项目
struct FolderHeaderRow: View {
    let folder: ArchiveFolder
    let isExpanded: Bool
    let level: Int
    let onTap: () -> Void
    weak var service: ProjectService?
    let allProjects: [Project]
    let allFolders: [ArchiveFolder]
    @Binding var expandedFolderIds: Set<UUID>
    @Binding var draggingActiveProjectId: UUID?
    @Binding var activeProjectDropTarget: ActiveProjectDropTarget?
    @Binding var draggingArchiveFolderId: UUID?
    @Binding var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @Binding var archiveProjectDropTargetFolderId: UUID?
    let onCreateSubfolder: (ArchiveFolder) -> Void
    let onRenameFolder: (ArchiveFolder) -> Void
    let onDeleteFolder: (ArchiveFolder) -> Void

    private var sortedProjects: [Project] {
        folder.projects.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var hasContents: Bool {
        !folder.children.isEmpty || !folder.projects.isEmpty
    }

    private var isDropTargetedInto: Bool {
        archiveFolderDropTarget == ArchiveFolderDropTarget(folderId: folder.folderId, placement: .into)
            || archiveProjectDropTargetFolderId == folder.folderId
    }

    var body: some View {
        HStack(spacing: 6) {
            if level > 0 {
                Spacer().frame(width: 16 * CGFloat(level))
            }

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(hasContents ? 1 : 0)
                .frame(width: 16, alignment: .center)

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(.secondary)
                .font(.title3)
                .frame(width: 22, alignment: .center)

            Text(folder.name)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if !sortedProjects.isEmpty {
                Text("\(sortedProjects.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            if isDropTargetedInto {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.blue.opacity(0.16))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(alignment: .top) {
            if archiveFolderDropTarget == ArchiveFolderDropTarget(folderId: folder.folderId, placement: .before) {
                ArchiveFolderDropIndicator()
            }
        }
        .overlay(alignment: .bottom) {
            if archiveFolderDropTarget == ArchiveFolderDropTarget(folderId: folder.folderId, placement: .after) {
                ArchiveFolderDropIndicator()
            }
        }
        .onDrag {
            draggingArchiveFolderId = folder.folderId
            return NSItemProvider(object: "folder:\(folder.folderId.uuidString)" as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: ArchiveFolderDropDelegate(
                folder: folder,
                service: service,
                allProjects: allProjects,
                allFolders: allFolders,
                expandedFolderIds: $expandedFolderIds,
                draggingActiveProjectId: $draggingActiveProjectId,
                activeProjectDropTarget: $activeProjectDropTarget,
                draggingFolderId: $draggingArchiveFolderId,
                dropTarget: $archiveFolderDropTarget,
                projectDropTargetFolderId: $archiveProjectDropTargetFolderId
            )
        )
        .contextMenu {
            Button {
                onCreateSubfolder(folder)
            } label: {
                Label("新建子文件夹", systemImage: "folder.badge.plus")
            }
            Button {
                onRenameFolder(folder)
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDeleteFolder(folder)
            } label: {
                Label("删除文件夹", systemImage: "trash")
            }
        }
    }
}

// MARK: - ArchivedProjectSelectableRow

/// 可点击查看详情的归档项目行，通过 Button 驱动 selection
struct ArchivedProjectSelectableRow: View {
    let project: Project
    let level: Int
    let indentPerLevel: CGFloat
    let isSelected: Bool
    var highlightRequestID: UUID? = nil
    let onDragStart: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Environment(ServiceContainer.self) private var container
    @State private var isHovered = false

    private var projectService: ProjectService? {
        container.projectService
    }

    private var accentColor: Color {
        project.progress >= 1.0
            ? ViabarColor.success
            : Color(hex: project.accentColor)
    }

    private var progressBarHeight: CGFloat {
        ActiveProjectRowMetrics.defaultProgressBarHeight
    }

    private var rowHeight: CGFloat {
        ActiveProjectRowMetrics.defaultRowHeight
    }

    private var horizontalInset: CGFloat {
        ActiveProjectRowMetrics.defaultHorizontalInset
    }

    private func rowContent(color: Color, usesProjectIconColor: Bool = false) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: indentPerLevel * CGFloat(level + 1))

            Spacer()
                .frame(width: 16)

            Image(systemName: project.sfSymbolName)
                .foregroundStyle(usesProjectIconColor ? accentColor : color)
                .font(.title3)
                .frame(width: 22, alignment: .center)

            Text(project.title)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(color)

            Spacer()
        }
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            ZStack(alignment: .center) {
                if !isSelected && isHovered {
                    Capsule(style: .continuous)
                        .fill(ActiveProjectRowMetrics.sidebarHoverColor)
                        .frame(height: progressBarHeight)
                }
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(ActiveProjectRowMetrics.progressTrackColor)
                        .frame(height: progressBarHeight)

                    GeometryReader { geo in
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.88))
                            .frame(
                                width: max(0, min(geo.size.width, geo.size.width * CGFloat(project.progress))),
                                height: progressBarHeight
                            )
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }

                rowContent(color: isSelected ? .primary : .secondary, usesProjectIconColor: true)

                if isSelected {
                    GeometryReader { geo in
                        let fillW = geo.size.width * CGFloat(project.progress)
                        rowContent(color: .white)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                            .mask(
                                HStack(spacing: 0) {
                                    Color.white.frame(width: fillW)
                                    Color.clear
                                }
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .searchTargetHighlight(
            triggerID: highlightRequestID,
            isActive: highlightRequestID != nil,
            cornerRadius: rowHeight / 2
        )
        .padding(.vertical, 0)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .onDrag {
            onDragStart()
            return NSItemProvider(object: project.projectId.uuidString as NSString)
        }
        .contextMenu {
            Button("取消归档") {
                projectService?.unarchiveProject(project)
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除项目", systemImage: "trash")
            }
        }
    }
}

// MARK: - ArchiveFolderDropDelegate

struct ArchiveFolderDropDelegate: DropDelegate {
    let folder: ArchiveFolder
    weak var service: ProjectService?
    let allProjects: [Project]
    let allFolders: [ArchiveFolder]
    @Binding var expandedFolderIds: Set<UUID>
    @Binding var draggingActiveProjectId: UUID?
    @Binding var activeProjectDropTarget: ActiveProjectDropTarget?
    @Binding var draggingFolderId: UUID?
    @Binding var dropTarget: ArchiveFolderDropTarget?
    @Binding var projectDropTargetFolderId: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }

        if let draggingFolderId {
            return draggingFolderId != folder.folderId
        }

        return draggingActiveProjectId != nil
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        guard draggingFolderId != nil || draggingActiveProjectId != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.folderId == folder.folderId {
            dropTarget = nil
        }
        if projectDropTargetFolderId == folder.folderId {
            projectDropTargetFolderId = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let svc = service else { return false }

        if let draggingFolderId,
           let sourceFolder = allFolders.first(where: { $0.folderId == draggingFolderId }) {
            moveFolder(sourceFolder, service: svc, info: info)
            resetDragState()
            return true
        }

        resetActiveProjectDragState()
        resetFolderDragState()

        let providers = info.itemProviders(for: [.plainText])
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let payload = item as? String,
                      !payload.hasPrefix("folder:"),
                      let uuid = UUID(uuidString: payload),
                      let project = allProjects.first(where: { $0.projectId == uuid })
                else { return }
                DispatchQueue.main.async {
                    if project.isArchived {
                        // 已在归档中 → 移动到目标文件夹
                        svc.moveProjectToFolder(project, folder: folder)
                    } else {
                        // 活跃项目 → 归档到目标文件夹
                        svc.archiveProject(project, to: folder)
                    }
                }
            }
        }
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard draggingFolderId != nil else {
            dropTarget = nil
            if draggingActiveProjectId != nil {
                projectDropTargetFolderId = folder.folderId
            } else {
                projectDropTargetFolderId = nil
            }
            return
        }

        projectDropTargetFolderId = nil

        guard let draggingFolderId,
              draggingFolderId != folder.folderId,
              let sourceFolder = allFolders.first(where: { $0.folderId == draggingFolderId }),
              !folder.isDescendant(of: sourceFolder)
        else {
            dropTarget = nil
            return
        }

        dropTarget = ArchiveFolderDropTarget(
            folderId: folder.folderId,
            placement: placement(for: info)
        )
    }

    private func placement(for info: DropInfo) -> ArchiveFolderDropPlacement {
        let edgeBand: CGFloat = 8

        if info.location.y <= edgeBand {
            return .before
        } else if info.location.y >= 30 - edgeBand {
            return .after
        } else {
            return .into
        }
    }

    private func moveFolder(_ sourceFolder: ArchiveFolder, service: ProjectService, info: DropInfo) {
        guard sourceFolder.folderId != folder.folderId,
              !folder.isDescendant(of: sourceFolder)
        else { return }

        let targetPlacement = dropTarget?.placement ?? placement(for: info)

        switch targetPlacement {
        case .into:
            service.moveFolder(sourceFolder, to: folder)
            expandedFolderIds.insert(folder.folderId)
        case .before, .after:
            moveFolderBesideTarget(sourceFolder, placement: targetPlacement, service: service)
        }
    }

    private func moveFolderBesideTarget(
        _ sourceFolder: ArchiveFolder,
        placement: ArchiveFolderDropPlacement,
        service: ProjectService
    ) {
        let targetParent = folder.parent

        if sourceFolder.parent?.folderId != targetParent?.folderId {
            service.moveFolder(sourceFolder, to: targetParent)
        }

        let siblings = allFolders.filter { candidate in
            candidate.parent?.folderId == targetParent?.folderId
        }
            .sorted { $0.orderIndex < $1.orderIndex }

        guard let sourceIndex = siblings.firstIndex(where: { $0.folderId == sourceFolder.folderId }),
              let targetIndex = siblings.firstIndex(where: { $0.folderId == folder.folderId })
        else { return }

        let destination = targetIndex + (placement == .after ? 1 : 0)
        guard sourceIndex != destination else { return }

        service.reorderFolders(in: targetParent, fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
    }

    private func resetActiveProjectDragState() {
        draggingActiveProjectId = nil
        activeProjectDropTarget = nil
        projectDropTargetFolderId = nil
    }

    private func resetFolderDragState() {
        draggingFolderId = nil
        dropTarget = nil
    }

    private func resetDragState() {
        resetActiveProjectDragState()
        resetFolderDragState()
    }
}

private extension ArchiveFolder {
    func isDescendant(of possibleAncestor: ArchiveFolder) -> Bool {
        var current = parent

        while let folder = current {
            if folder.folderId == possibleAncestor.folderId {
                return true
            }
            current = folder.parent
        }

        return false
    }
}

// MARK: - EmptyHintView

struct EmptyHintView: View {
    let icon: String
    let message: LocalizedStringKey
    let action: LocalizedStringKey
    let onAction: () -> Void

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Button(action, action: onAction)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }
}

// MARK: - Preview

private struct SidebarPreviewData {
    let serviceContainer: ServiceContainer
    let modelContainer: ModelContainer
    let selectedProject: Project

    @MainActor
    static func make() -> SidebarPreviewData {
        let schema = Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
            TrashItem.self,
            AppSettings.self,
            NotificationScheduleEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        let serviceContainer = ServiceContainer()
        let projectService = ProjectService(modelContext: modelContainer.mainContext, container: serviceContainer)
        let scheduleService = NotificationScheduleService(modelContext: modelContainer.mainContext, notificationPoster: { _, _ in })
        let trashService = TrashService(
            modelContext: modelContainer.mainContext,
            projectModelContext: modelContainer.mainContext,
            notificationScheduleService: scheduleService
        )
        serviceContainer.register(projectService)
        serviceContainer.register(scheduleService)
        serviceContainer.register(trashService)
        modelContainer.mainContext.insert(AppSettings())

        let version = makeProject(title: "版本", accentColor: ViabarColor.primaryHex, symbol: "bookmark.fill", completed: 1, total: 6, order: 0, context: modelContainer.mainContext)
        _ = makeProject(title: "5553", accentColor: "#4CC3FF", symbol: "circle.dashed", completed: 0, total: 4, order: 1, context: modelContainer.mainContext)
        _ = makeProject(title: "发给", accentColor: "#5BD10E", symbol: "circle.dashed", completed: 0, total: 3, order: 2, context: modelContainer.mainContext)
        _ = makeProject(title: "22", accentColor: "#60C4F8", symbol: "circle.dashed", completed: 1, total: 3, order: 3, context: modelContainer.mainContext)
        _ = makeProject(title: "123", accentColor: "#60C4F8", symbol: "circle.dashed", completed: 1, total: 5, order: 4, context: modelContainer.mainContext)
        _ = makeProject(title: "呜呜呜", accentColor: "#48D0A8", symbol: "circle.dashed", completed: 4, total: 4, order: 5, context: modelContainer.mainContext)

        try? modelContainer.mainContext.save()

        return SidebarPreviewData(
            serviceContainer: serviceContainer,
            modelContainer: modelContainer,
            selectedProject: version
        )
    }

    @MainActor
    private static func makeProject(
        title: String,
        accentColor: String,
        symbol: String,
        completed: Int,
        total: Int,
        order: Int,
        context: ModelContext
    ) -> Project {
        let project = Project(title: title, orderIndex: order)
        project.accentColor = accentColor
        project.sfSymbolName = symbol
        context.insert(project)

        for index in 0..<total {
            let milestone = Milestone(title: "任务 \(index + 1)", orderIndex: index, isCompleted: index < completed)
            milestone.project = project
            context.insert(milestone)
        }

        return project
    }
}

private struct SidebarPreviewHost: View {
    let data: SidebarPreviewData
    @State private var selection: SidebarSelection?

    init() {
        let data = SidebarPreviewData.make()
        self.data = data
        _selection = State(initialValue: .project(data.selectedProject))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            Text("Detail")
        }
        .environment(data.serviceContainer)
        .modelContainer(data.modelContainer)
    }
}

#Preview("Sidebar Light") {
    SidebarPreviewHost()
        .preferredColorScheme(.light)
}

#Preview("Sidebar Dark") {
    SidebarPreviewHost()
        .preferredColorScheme(.dark)
}
