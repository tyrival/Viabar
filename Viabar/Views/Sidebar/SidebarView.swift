import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private let projectDropLogStart = Date()

private func projectDropLog(_ message: String) {
    let elapsed = Date().timeIntervalSince(projectDropLogStart)
    print(String(format: "[ProjectDrop +%.3fs] %@", elapsed, message))
}

private func sidebarContextLog(_ message: String) {
    print("[SidebarContext] \(message)")
}

private struct RightClickContextReader: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RightClickContextView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RightClickContextView)?.onRightClick = onRightClick
    }

    private final class RightClickContextView: NSView {
        var onRightClick: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
            super.rightMouseDown(with: event)
        }
    }
}

private enum SidebarMenuEntry {
    case item(String, systemImage: String? = nil, action: () -> Void)
    case separator
}

private struct SidebarRightClickMenu: NSViewRepresentable {
    let source: String
    let entries: () -> [SidebarMenuEntry]
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> MenuHostView {
        let view = MenuHostView()
        view.source = source
        view.entries = entries
        view.onRightClick = onRightClick
        view.installMonitor()
        return view
    }

    func updateNSView(_ nsView: MenuHostView, context: Context) {
        nsView.source = source
        nsView.entries = entries
        nsView.onRightClick = onRightClick
    }

    static func dismantleNSView(_ nsView: MenuHostView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class MenuHostView: NSView {
        var source = ""
        var entries: (() -> [SidebarMenuEntry])?
        var onRightClick: (() -> Void)?
        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self,
                      let window,
                      event.window === window
                else { return event }

                let pointInView = convert(event.locationInWindow, from: nil)
                guard bounds.contains(pointInView) else { return event }

                onRightClick?()
                sidebarContextLog("show menu source=\(source) point=\(String(format: "%.1f,%.1f", pointInView.x, pointInView.y)) bounds=\(String(format: "%.1fx%.1f", bounds.width, bounds.height))")
                let menu = NSMenu()
                for entry in entries?() ?? [] {
                    switch entry {
                    case .separator:
                        menu.addItem(.separator())
                    case .item(let title, let systemImage, let action):
                        let item = ClosureMenuItem(title: title, action: #selector(ClosureMenuItem.invoke), keyEquivalent: "")
                        item.handler = action
                        item.target = item
                        if let systemImage {
                            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
                        }
                        menu.addItem(item)
                    }
                }
                menu.popUp(positioning: nil, at: pointInView, in: self)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }

    private final class ClosureMenuItem: NSMenuItem {
        var handler: (() -> Void)?

        @objc func invoke() {
            handler?()
        }
    }
}

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
    @State private var activeProjectDisplayOrder: [UUID]?
    @State private var isCommittingActiveProjectDrop = false
    @State private var draggingArchiveFolderId: UUID?
    @State private var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @State private var archiveProjectDropTargetFolderId: UUID?
    @State private var archiveProjectDropTarget: ArchiveProjectDropTarget?
    @State private var archiveRootDropHighlighted = false
    @State private var archiveFolderDisplayOrderByParent: [ArchiveOrderScope: [UUID]] = [:]
    @State private var archiveProjectDisplayOrderByFolder: [ArchiveOrderScope: [UUID]] = [:]
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
    @State private var contextProjectId: UUID?
    @State private var contextArchiveFolderId: UUID?

    private var projectService: ProjectService? {
        container.projectService
    }

    private func setContextProject(_ project: Project, source: String) {
        contextProjectId = project.projectId
        sidebarContextLog("set project source=\(source) title=\(project.title) id=\(project.projectId)")
    }

    private func setContextArchiveFolder(_ folder: ArchiveFolder, source: String) {
        contextArchiveFolderId = folder.folderId
        sidebarContextLog("set folder source=\(source) name=\(folder.name) id=\(folder.folderId)")
    }

    private func contextProject(fallback project: Project) -> Project {
        guard let contextProjectId,
              let target = allProjects.first(where: { $0.projectId == contextProjectId })
        else {
            sidebarContextLog("resolve project fallback title=\(project.title) id=\(project.projectId) context=\(contextProjectId?.uuidString ?? "nil")")
            return project
        }
        sidebarContextLog("resolve project fallback=\(project.title) -> target=\(target.title) id=\(target.projectId)")
        return target
    }

    private func contextArchiveFolder(fallback folder: ArchiveFolder) -> ArchiveFolder {
        guard let contextArchiveFolderId,
              let target = allFolders.first(where: { $0.folderId == contextArchiveFolderId })
        else {
            sidebarContextLog("resolve folder fallback name=\(folder.name) id=\(folder.folderId) context=\(contextArchiveFolderId?.uuidString ?? "nil")")
            return folder
        }
        sidebarContextLog("resolve folder fallback=\(folder.name) -> target=\(target.name) id=\(target.folderId)")
        return target
    }

    private func selectionDescription(_ value: SidebarSelection?) -> String {
        switch value {
        case .overview:
            return "overview"
        case .project(let project):
            return "project title=\(project.title) id=\(project.projectId)"
        case nil:
            return "nil"
        }
    }

    private var activeProjects: [Project] {
        allProjects.filter { !$0.isArchived }
    }

    private var displayedActiveProjects: [Project] {
        guard let activeProjectDisplayOrder else {
            return activeProjects
        }

        var projectsByID = Dictionary(uniqueKeysWithValues: activeProjects.map { ($0.projectId, $0) })
        var displayedProjects = activeProjectDisplayOrder.compactMap { projectsByID.removeValue(forKey: $0) }
        displayedProjects.append(contentsOf: activeProjects.filter { projectsByID[$0.projectId] != nil })
        return displayedProjects
    }

    private var selectedActiveProjectId: UUID? {
        if case .project(let project) = selection {
            return project.projectId
        }
        return nil
    }

    private var rootFolders: [ArchiveFolder] {
        allFolders.filter { $0.parent == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var displayedRootFolders: [ArchiveFolder] {
        displayedFolders(rootFolders, scope: .root)
    }

    private var rootArchivedProjects: [Project] {
        allProjects
            .filter { $0.isArchived && $0.archiveFolder == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var displayedRootArchivedProjects: [Project] {
        displayedProjects(rootArchivedProjects, scope: .root)
    }

    private func displayedFolders(_ folders: [ArchiveFolder], scope: ArchiveOrderScope) -> [ArchiveFolder] {
        guard let order = archiveFolderDisplayOrderByParent[scope] else {
            return folders
        }
        var byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.folderId, $0) })
        var displayed = order.compactMap { byID.removeValue(forKey: $0) }
        displayed.append(contentsOf: folders.filter { byID[$0.folderId] != nil })
        return displayed
    }

    private func displayedProjects(_ projects: [Project], scope: ArchiveOrderScope) -> [Project] {
        guard let order = archiveProjectDisplayOrderByFolder[scope] else {
            return projects
        }
        var byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        var displayed = order.compactMap { byID.removeValue(forKey: $0) }
        displayed.append(contentsOf: projects.filter { byID[$0.projectId] != nil })
        return displayed
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
        .onChange(of: selection) { oldValue, newValue in
            sidebarContextLog("selection old=\(selectionDescription(oldValue)) new=\(selectionDescription(newValue))")
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
                VStack(spacing: ActiveProjectRowMetrics.projectRowSpacing) {
                    ForEach(displayedActiveProjects, id: \.projectId) { project in
                        ActiveProjectRow(
                            project: project,
                            isSelected: selection == .project(project),
                            highlightRequestID: projectHighlightRequestID(for: project),
                            isFavoriteForContext: {
                                contextProject(fallback: project).isFavorite
                            },
                            onEdit: {
                                sidebarContextLog("action active.edit fallback=\(project.title)")
                                editingProject = contextProject(fallback: project)
                            },
                            onArchive: {
                                sidebarContextLog("action active.archive fallback=\(project.title)")
                                archivePickerProject = contextProject(fallback: project)
                            },
                            onToggleFavorite: {
                                sidebarContextLog("action active.favorite fallback=\(project.title)")
                                projectService?.toggleFavorite(contextProject(fallback: project))
                            },
                            onDelete: {
                                sidebarContextLog("action active.delete fallback=\(project.title)")
                                showDeleteProjectConfirmation(contextProject(fallback: project))
                            },
                            onSelect: {
                                selection = .project(project)
                            }
                        )
                        .onHover { hovering in
                            if hovering {
                                setContextProject(project, source: "active.hover")
                            }
                        }
                        .background {
                            RightClickContextReader {
                                setContextProject(project, source: "active.rightMouseDown")
                            }
                        }
                        .onDrag {
                            draggingActiveProjectId = project.projectId
                            activeProjectDisplayOrder = displayedActiveProjects.map(\.projectId)
                            projectDropLog("drag start project=\(project.title) id=\(project.projectId)")
                            let provider = NSItemProvider(object: project.projectId.uuidString as NSString)
                            return provider
                        }
                    }
                }
                .overlay {
                    ActiveProjectDropOverlay(
                        projects: displayedActiveProjects,
                        selectedProjectId: selectedActiveProjectId,
                        draggingProjectId: draggingActiveProjectId,
                        service: projectService,
                        draggingProjectIdBinding: $draggingActiveProjectId,
                        dropTarget: $activeProjectDropTarget,
                        displayOrderOverride: $activeProjectDisplayOrder,
                        isCommittingDrop: $isCommittingActiveProjectDrop
                    )
                }
                .selectionDisabled()
                .focusable(false)
                .focusEffectDisabled()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onChange(of: draggingActiveProjectId) { _, newValue in
                    projectDropLog("draggingActiveProjectId changed to \(newValue?.uuidString ?? "nil")")
                    if newValue == nil {
                        projectDropLog("clear drop target because dragging project is nil")
                        activeProjectDropTarget = nil
                        if !isCommittingActiveProjectDrop {
                            activeProjectDisplayOrder = nil
                        }
                    }
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
            .contentShape(Rectangle())
            .onDrop(
                of: [.plainText],
                delegate: ArchiveRootDropDelegate(
                    allProjects: allProjects,
                    allFolders: allFolders,
                    rootArchivedProjects: rootArchivedProjects,
                    service: projectService,
                    isArchiveExpanded: $isArchiveExpanded,
                    isHighlighted: $archiveRootDropHighlighted,
                    folderDisplayOrderByParent: $archiveFolderDisplayOrderByParent,
                    projectDisplayOrderByFolder: $archiveProjectDisplayOrderByFolder,
                    draggingProjectId: $draggingActiveProjectId,
                    draggingFolderId: $draggingArchiveFolderId,
                    activeProjectDropTarget: $activeProjectDropTarget,
                    archiveFolderDropTarget: $archiveFolderDropTarget,
                    archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                    archiveProjectDropTarget: $archiveProjectDropTarget
                )
            )
            .background {
                if archiveRootDropHighlighted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.blue.opacity(0.16))
                        .padding(.horizontal, ActiveProjectRowMetrics.defaultHorizontalInset)
                }
            }
        }
    }

    @ViewBuilder
    private var archiveContent: some View {
        if rootFolders.isEmpty && rootArchivedProjects.isEmpty {
            EmptyHintView(
                icon: "archivebox",
                message: "暂无归档文件夹",
                action: "创建文件夹",
                onAction: { showCreateRootFolderPrompt() }
            )
        } else {
            VStack(spacing: 0) {
                ForEach(displayedRootFolders, id: \.folderId) { folder in
                    ArchiveFolderBranchView(
                        folder: folder,
                        level: 0,
                        selection: $selection,
                        projectHighlightRequest: revealRequest,
                        expandedFolderIds: $expandedFolderIds,
                        draggingActiveProjectId: $draggingActiveProjectId,
                        draggingArchiveFolderId: $draggingArchiveFolderId,
                        archiveFolderDropTarget: $archiveFolderDropTarget,
                        archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                        folderDisplayOrderByParent: $archiveFolderDisplayOrderByParent,
                        projectDisplayOrderByFolder: $archiveProjectDisplayOrderByFolder,
                        contextProjectId: $contextProjectId,
                        contextArchiveFolderId: $contextArchiveFolderId,
                        allProjects: allProjects,
                        allFolders: allFolders,
                        service: projectService,
                        onCreateSubfolder: { folder in
                            sidebarContextLog("action folder.createChild fallback=\(folder.name)")
                            showCreateSubfolderPrompt(parent: contextArchiveFolder(fallback: folder))
                        },
                        onRenameFolder: { folder in
                            sidebarContextLog("action folder.rename fallback=\(folder.name)")
                            showRenameFolderPrompt(folder: contextArchiveFolder(fallback: folder))
                        },
                        onDeleteFolder: { folder in
                            sidebarContextLog("action folder.delete fallback=\(folder.name)")
                            requestDeleteFolder(contextArchiveFolder(fallback: folder))
                        },
                        onUnarchiveProject: { project in
                            sidebarContextLog("action archiveProject.unarchive fallback=\(project.title)")
                            projectService?.unarchiveProject(contextProject(fallback: project))
                        },
                        onDeleteProject: { project in
                            sidebarContextLog("action archiveProject.delete fallback=\(project.title)")
                            showDeleteProjectConfirmation(contextProject(fallback: project))
                        },
                        onSelectProject: { selection = .project($0) }
                    )
                    .id(folder.folderId)
                }

                ForEach(displayedRootArchivedProjects, id: \.projectId) { project in
                    ArchivedProjectSelectableRow(
                        project: project,
                        level: 0,
                        indentPerLevel: ArchiveTreeMetrics.indentPerLevel,
                        isSelected: selection == .project(project),
                        highlightRequestID: projectHighlightRequestID(for: project),
                        showsTopDropLine: false,
                        showsBottomDropLine: false,
                        onDragStart: {
                            draggingActiveProjectId = project.projectId
                        },
                        onContextTarget: {
                            setContextProject(project, source: "archiveRootProject.contextTarget")
                        },
                        onUnarchive: {
                            sidebarContextLog("action archiveRootProject.unarchive fallback=\(project.title)")
                            projectService?.unarchiveProject(contextProject(fallback: project))
                        },
                        onDelete: {
                            sidebarContextLog("action archiveRootProject.delete fallback=\(project.title)")
                            showDeleteProjectConfirmation(contextProject(fallback: project))
                        }
                    ) {
                        selection = .project(project)
                    }
                    .id(project.projectId)
                    .onHover { hovering in
                        if hovering {
                            setContextProject(project, source: "archiveRootProject.hover")
                        }
                    }
                    .background {
                        RightClickContextReader {
                            setContextProject(project, source: "archiveRootProject.rightMouseDown")
                        }
                    }
                    .onDrop(
                        of: [.plainText],
                        delegate: ArchiveProjectNestedDropDelegate(
                            targetProject: project,
                            targetFolder: nil,
                            allProjects: allProjects,
                            service: projectService,
                            draggingProjectId: $draggingActiveProjectId,
                            activeProjectDropTarget: $activeProjectDropTarget,
                            archiveFolderDropTarget: $archiveFolderDropTarget,
                            archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                            archiveProjectDropTarget: $archiveProjectDropTarget,
                            projectDisplayOrderByFolder: $archiveProjectDisplayOrderByFolder
                        )
                    )
                }
            }
            .selectionDisabled()
            .focusable(false)
            .focusEffectDisabled()
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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

// MARK: - Archive Tree Rows

private enum ArchiveOrderScope: Hashable {
    case root
    case folder(UUID)

    static func parent(_ folder: ArchiveFolder?) -> ArchiveOrderScope {
        if let folder {
            return .folder(folder.folderId)
        }
        return .root
    }
}

private enum ArchiveTreeMetrics {
    static let indentPerLevel: CGFloat = 16
    static let rowHeight: CGFloat = ActiveProjectRowMetrics.defaultRowHeight
    static let folderEdgeDropBand: CGFloat = 8
}

private struct ArchiveFolderFlatRow: View {
    let folder: ArchiveFolder
    let isExpanded: Bool
    let level: Int
    let isDropTargetedInto: Bool
    let onToggle: () -> Void
    let onDragStart: () -> Void
    let onCreateSubfolder: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var hasContents: Bool {
        !folder.children.isEmpty || !folder.projects.isEmpty
    }

    private var backgroundFill: Color {
        if isDropTargetedInto {
            return .blue.opacity(0.16)
        }
        return isHovered ? ActiveProjectRowMetrics.sidebarHoverColor : .clear
    }

    private var rowForeground: Color {
        isHovered ? .primary : .secondary
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            if level > 0 {
                Spacer().frame(width: ArchiveTreeMetrics.indentPerLevel * CGFloat(level))
            }

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(hasContents ? 1 : 0)
                .frame(width: 16, alignment: .center)

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(rowForeground)
                .font(.title3)
                .frame(width: 22, alignment: .center)

            Text(folder.name)
                .font(.body)
                .foregroundStyle(rowForeground)
                .lineLimit(1)

            Spacer()

            if !folder.projects.isEmpty {
                Text("\(folder.projects.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dragPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(.secondary)
                .font(.title3)
                .frame(width: 22, alignment: .center)

            Text(folder.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: ArchiveTreeMetrics.rowHeight)
        .background {
            Capsule(style: .continuous)
                .fill(ActiveProjectRowMetrics.sidebarHoverColor)
        }
    }

    var body: some View {
        rowContent
        .frame(maxWidth: .infinity, minHeight: ArchiveTreeMetrics.rowHeight, alignment: .leading)
        .padding(.horizontal, ActiveProjectRowMetrics.defaultHorizontalInset)
        .background {
            if isDropTargetedInto || isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundFill)
                    .padding(.horizontal, ActiveProjectRowMetrics.defaultHorizontalInset)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onHover { isHovered = $0 }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: "folder:\(folder.folderId.uuidString)" as NSString)
        } preview: {
            dragPreview
        }
        .background {
            SidebarRightClickMenu(source: "archiveFolder:\(folder.name)") {
                [
                    .item("新建子文件夹", systemImage: "folder.badge.plus", action: onCreateSubfolder),
                    .item("重命名", systemImage: "pencil", action: onRename),
                    .separator,
                    .item("删除文件夹", systemImage: "trash", action: onDelete)
                ]
            } onRightClick: {
                sidebarContextLog("row rightClick archiveFolder name=\(folder.name) id=\(folder.folderId)")
            }
        }
    }
}

private struct ArchiveFolderBranchView: View {
    let folder: ArchiveFolder
    let level: Int
    @Binding var selection: SidebarSelection?
    let projectHighlightRequest: GlobalSearchNavigationRequest?
    @Binding var expandedFolderIds: Set<UUID>
    @Binding var draggingActiveProjectId: UUID?
    @Binding var draggingArchiveFolderId: UUID?
    @Binding var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @Binding var archiveProjectDropTargetFolderId: UUID?
    @Binding var folderDisplayOrderByParent: [ArchiveOrderScope: [UUID]]
    @Binding var projectDisplayOrderByFolder: [ArchiveOrderScope: [UUID]]
    @Binding var contextProjectId: UUID?
    @Binding var contextArchiveFolderId: UUID?
    let allProjects: [Project]
    let allFolders: [ArchiveFolder]
    weak var service: ProjectService?
    let onCreateSubfolder: (ArchiveFolder) -> Void
    let onRenameFolder: (ArchiveFolder) -> Void
    let onDeleteFolder: (ArchiveFolder) -> Void
    let onUnarchiveProject: (Project) -> Void
    let onDeleteProject: (Project) -> Void
    let onSelectProject: (Project) -> Void

    private var isExpanded: Bool {
        expandedFolderIds.contains(folder.folderId)
    }

    private var sortedChildren: [ArchiveFolder] {
        displayedFolders(folder.children.sorted { $0.orderIndex < $1.orderIndex }, parent: folder)
    }

    private var sortedProjects: [Project] {
        displayedProjects(folder.projects.sorted { $0.orderIndex < $1.orderIndex }, folder: folder)
    }

    private func displayedFolders(_ folders: [ArchiveFolder], parent: ArchiveFolder?) -> [ArchiveFolder] {
        let scope = ArchiveOrderScope.parent(parent)
        guard let order = folderDisplayOrderByParent[scope] else {
            return folders
        }
        var byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.folderId, $0) })
        var displayed = order.compactMap { byID.removeValue(forKey: $0) }
        displayed.append(contentsOf: folders.filter { byID[$0.folderId] != nil })
        return displayed
    }

    private func displayedProjects(_ projects: [Project], folder: ArchiveFolder?) -> [Project] {
        let scope = ArchiveOrderScope.parent(folder)
        guard let order = projectDisplayOrderByFolder[scope] else {
            return projects
        }
        var byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        var displayed = order.compactMap { byID.removeValue(forKey: $0) }
        displayed.append(contentsOf: projects.filter { byID[$0.projectId] != nil })
        return displayed
    }

    private func projectHighlightRequestID(for project: Project) -> UUID? {
        guard projectHighlightRequest?.projectID == project.projectId,
              case .some(.project) = projectHighlightRequest?.destination
        else { return nil }
        return projectHighlightRequest?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ArchiveFolderFlatRow(
                folder: folder,
                isExpanded: isExpanded,
                level: level,
                isDropTargetedInto: archiveFolderDropTarget == ArchiveFolderDropTarget(folderId: folder.folderId, placement: .into)
                    || archiveProjectDropTargetFolderId == folder.folderId,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        if isExpanded {
                            expandedFolderIds.remove(folder.folderId)
                        } else {
                            expandedFolderIds.insert(folder.folderId)
                        }
                    }
                },
                onDragStart: {
                    draggingArchiveFolderId = folder.folderId
                },
                onCreateSubfolder: { onCreateSubfolder(folder) },
                onRename: { onRenameFolder(folder) },
                onDelete: { onDeleteFolder(folder) }
            )
            .id(folder.folderId)
            .onHover { hovering in
                if hovering {
                    contextArchiveFolderId = folder.folderId
                    sidebarContextLog("set folder source=folder.hover name=\(folder.name) id=\(folder.folderId)")
                }
            }
            .background {
                RightClickContextReader {
                    contextArchiveFolderId = folder.folderId
                    sidebarContextLog("set folder source=folder.rightMouseDown name=\(folder.name) id=\(folder.folderId)")
                }
            }
            .onDrop(
                of: [.plainText],
                delegate: ArchiveFolderNestedDropDelegate(
                    targetFolder: folder,
                    allProjects: allProjects,
                    allFolders: allFolders,
                    service: service,
                    expandedFolderIds: $expandedFolderIds,
                    draggingProjectId: $draggingActiveProjectId,
                    draggingFolderId: $draggingArchiveFolderId,
                    archiveFolderDropTarget: $archiveFolderDropTarget,
                    archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                    folderDisplayOrderByParent: $folderDisplayOrderByParent
                )
            )

            if isExpanded {
                ForEach(sortedChildren, id: \.folderId) { child in
                    ArchiveFolderBranchView(
                        folder: child,
                        level: level + 1,
                        selection: $selection,
                        projectHighlightRequest: projectHighlightRequest,
                        expandedFolderIds: $expandedFolderIds,
                        draggingActiveProjectId: $draggingActiveProjectId,
                        draggingArchiveFolderId: $draggingArchiveFolderId,
                        archiveFolderDropTarget: $archiveFolderDropTarget,
                        archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                        folderDisplayOrderByParent: $folderDisplayOrderByParent,
                        projectDisplayOrderByFolder: $projectDisplayOrderByFolder,
                        contextProjectId: $contextProjectId,
                        contextArchiveFolderId: $contextArchiveFolderId,
                        allProjects: allProjects,
                        allFolders: allFolders,
                        service: service,
                        onCreateSubfolder: onCreateSubfolder,
                        onRenameFolder: onRenameFolder,
                        onDeleteFolder: onDeleteFolder,
                        onUnarchiveProject: onUnarchiveProject,
                        onDeleteProject: onDeleteProject,
                        onSelectProject: onSelectProject
                    )
                    .id(child.folderId)
                }

                ForEach(sortedProjects, id: \.projectId) { project in
                    ArchivedProjectSelectableRow(
                        project: project,
                        level: level + 1,
                        indentPerLevel: ArchiveTreeMetrics.indentPerLevel,
                        isSelected: selection == .project(project),
                        highlightRequestID: projectHighlightRequestID(for: project),
                        showsTopDropLine: false,
                        showsBottomDropLine: false,
                        onDragStart: {
                            draggingActiveProjectId = project.projectId
                        },
                        onContextTarget: {
                            contextProjectId = project.projectId
                            sidebarContextLog("set project source=archiveProject.contextTarget title=\(project.title) id=\(project.projectId)")
                        },
                        onUnarchive: { onUnarchiveProject(project) },
                        onDelete: { onDeleteProject(project) }
                    ) {
                        onSelectProject(project)
                    }
                    .id(project.projectId)
                    .onHover { hovering in
                        if hovering {
                            contextProjectId = project.projectId
                            sidebarContextLog("set project source=archiveProject.hover title=\(project.title) id=\(project.projectId)")
                        }
                    }
                    .background {
                        RightClickContextReader {
                            contextProjectId = project.projectId
                            sidebarContextLog("set project source=archiveProject.rightMouseDown title=\(project.title) id=\(project.projectId)")
                        }
                    }
                    .onDrop(
                        of: [.plainText],
                        delegate: ArchiveProjectNestedDropDelegate(
                            targetProject: project,
                            targetFolder: folder,
                            allProjects: allProjects,
                            service: service,
                            draggingProjectId: $draggingActiveProjectId,
                            activeProjectDropTarget: .constant(nil),
                            archiveFolderDropTarget: $archiveFolderDropTarget,
                            archiveProjectDropTargetFolderId: $archiveProjectDropTargetFolderId,
                            archiveProjectDropTarget: .constant(nil),
                            projectDisplayOrderByFolder: $projectDisplayOrderByFolder
                        )
                    )
                }
            }
        }
    }
}

private struct ArchiveFolderNestedDropDelegate: DropDelegate {
    let targetFolder: ArchiveFolder
    let allProjects: [Project]
    let allFolders: [ArchiveFolder]
    weak var service: ProjectService?
    @Binding var expandedFolderIds: Set<UUID>
    @Binding var draggingProjectId: UUID?
    @Binding var draggingFolderId: UUID?
    @Binding var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @Binding var archiveProjectDropTargetFolderId: UUID?
    @Binding var folderDisplayOrderByParent: [ArchiveOrderScope: [UUID]]

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        return draggingProjectId != nil || draggingFolderId != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if draggingFolderId != nil {
            updateFolderTarget(info: info)
        } else if draggingProjectId != nil {
            archiveFolderDropTarget = nil
            archiveProjectDropTargetFolderId = targetFolder.folderId
        }
        guard draggingProjectId != nil || draggingFolderId != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearTargets()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let service else {
            resetState()
            return false
        }

        if let draggingFolderId,
           let sourceFolder = allFolders.first(where: { $0.folderId == draggingFolderId }) {
            performFolderDrop(sourceFolder, service: service, info: info)
            resetState()
            return true
        }

        if let draggingProjectId,
           let project = allProjects.first(where: { $0.projectId == draggingProjectId }) {
            let endOffset = targetFolder.projects.filter { $0.projectId != project.projectId }.count
            service.moveProjectToFolder(project, folder: targetFolder, toOffset: endOffset)
            expandedFolderIds.insert(targetFolder.folderId)
            resetState()
            return true
        }

        resetState()
        return false
    }

    private func updateFolderTarget(info: DropInfo) {
        guard let draggingFolderId,
              let sourceFolder = allFolders.first(where: { $0.folderId == draggingFolderId }),
              sourceFolder.folderId != targetFolder.folderId,
              !targetFolder.isDescendant(of: sourceFolder)
        else {
            archiveFolderDropTarget = nil
            return
        }

        let placement = folderPlacement(for: info)
        guard placement == .into || sourceFolder.parent?.folderId == targetFolder.parent?.folderId else {
            archiveFolderDropTarget = nil
            return
        }
        archiveFolderDropTarget = ArchiveFolderDropTarget(folderId: targetFolder.folderId, placement: placement)
        if placement == .before || placement == .after {
            updateFolderDisplayOrder(sourceFolder: sourceFolder, placement: placement)
        }
    }

    private func performFolderDrop(_ sourceFolder: ArchiveFolder, service: ProjectService, info: DropInfo) {
        if persistFolderDisplayOrder(in: sourceFolder.parent, service: service) {
            return
        }

        guard sourceFolder.folderId != targetFolder.folderId,
              !targetFolder.isDescendant(of: sourceFolder)
        else { return }

        let placement = archiveFolderDropTarget?.placement ?? folderPlacement(for: info)
        switch placement {
        case .into:
            service.moveFolder(sourceFolder, to: targetFolder)
            expandedFolderIds.insert(targetFolder.folderId)
        case .before, .after:
            guard sourceFolder.parent?.folderId == targetFolder.parent?.folderId else { return }
            let targetParent = targetFolder.parent
            let siblings = allFolders
                .filter { $0.parent?.folderId == targetParent?.folderId }
                .sorted { $0.orderIndex < $1.orderIndex }
            guard let sourceIndex = siblings.firstIndex(where: { $0.folderId == sourceFolder.folderId }),
                  let targetIndex = siblings.firstIndex(where: { $0.folderId == targetFolder.folderId })
            else { return }
            let destination = placement == .after ? targetIndex + 1 : targetIndex
            service.reorderFolders(in: targetParent, fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        }
    }

    private func updateFolderDisplayOrder(sourceFolder: ArchiveFolder, placement: ArchiveFolderDropPlacement) {
        let targetParent = targetFolder.parent
        let scope = ArchiveOrderScope.parent(targetParent)
        let naturalIDs = allFolders
            .filter { $0.parent?.folderId == targetParent?.folderId }
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(\.folderId)
        var ids = folderDisplayOrderByParent[scope] ?? naturalIDs
        guard let sourceIndex = ids.firstIndex(of: sourceFolder.folderId),
              let targetIndex = ids.firstIndex(of: targetFolder.folderId)
        else { return }
        let destination = placement == .after ? targetIndex + 1 : targetIndex
        ids.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        withAnimation(.easeInOut(duration: 0.12)) {
            folderDisplayOrderByParent[scope] = ids
        }
    }

    private func persistFolderDisplayOrder(in parent: ArchiveFolder?, service: ProjectService) -> Bool {
        let scope = ArchiveOrderScope.parent(parent)
        guard let orderedIDs = folderDisplayOrderByParent[scope] else { return false }
        var foldersByID = Dictionary(uniqueKeysWithValues: allFolders.map { ($0.folderId, $0) })
        let orderedFolders = orderedIDs.compactMap { foldersByID.removeValue(forKey: $0) }
        guard !orderedFolders.isEmpty else { return false }
        for (index, folder) in orderedFolders.enumerated() {
            folder.orderIndex = index
        }
        service.save()
        return true
    }

    private func folderPlacement(for info: DropInfo) -> ArchiveFolderDropPlacement {
        if info.location.y <= ArchiveTreeMetrics.folderEdgeDropBand {
            return .before
        } else if info.location.y >= ArchiveTreeMetrics.rowHeight - ArchiveTreeMetrics.folderEdgeDropBand {
            return .after
        } else {
            return .into
        }
    }

    private func clearTargets() {
        archiveFolderDropTarget = nil
        archiveProjectDropTargetFolderId = nil
    }

    private func resetState() {
        draggingFolderId = nil
        draggingProjectId = nil
        clearTargets()
        folderDisplayOrderByParent.removeAll()
    }
}

private struct ArchiveProjectNestedDropDelegate: DropDelegate {
    let targetProject: Project
    let targetFolder: ArchiveFolder?
    let allProjects: [Project]
    weak var service: ProjectService?
    @Binding var draggingProjectId: UUID?
    @Binding var activeProjectDropTarget: ActiveProjectDropTarget?
    @Binding var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @Binding var archiveProjectDropTargetFolderId: UUID?
    @Binding var archiveProjectDropTarget: ArchiveProjectDropTarget?
    @Binding var projectDisplayOrderByFolder: [ArchiveOrderScope: [UUID]]

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]),
              let draggingProjectId,
              draggingProjectId != targetProject.projectId,
              let draggingProject = allProjects.first(where: { $0.projectId == draggingProjectId })
        else { return false }
        return draggingProject.archiveFolder?.folderId == targetFolder?.folderId
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            clearTargets()
            return nil
        }
        archiveFolderDropTarget = nil
        archiveProjectDropTargetFolderId = nil
        archiveProjectDropTarget = ArchiveProjectDropTarget(
            projectId: targetProject.projectId,
            placement: projectPlacement(for: info)
        )
        updateProjectDisplayOrder(placement: projectPlacement(for: info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearTargets()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let service,
              let draggingProjectId,
              let project = allProjects.first(where: { $0.projectId == draggingProjectId })
        else {
            resetState()
            return false
        }

        if persistProjectDisplayOrder(in: project.archiveFolder, service: service) {
            resetState()
            return true
        }

        guard project.projectId != targetProject.projectId,
              project.archiveFolder?.folderId == targetFolder?.folderId
        else {
            resetState()
            return false
        }

        let placement = projectPlacement(for: info)
        let siblings = allProjects
            .filter { candidate in
                candidate.isArchived
                    && candidate.projectId != project.projectId
                    && candidate.archiveFolder?.folderId == targetFolder?.folderId
            }
            .sorted { $0.orderIndex < $1.orderIndex }
        guard let targetIndex = siblings.firstIndex(where: { $0.projectId == targetProject.projectId }) else {
            resetState()
            return false
        }

        let offset = placement == .after ? targetIndex + 1 : targetIndex
        if let targetFolder {
            service.moveProjectToFolder(project, folder: targetFolder, toOffset: offset)
        } else {
            service.moveProjectToArchiveRoot(project, toOffset: offset)
        }
        resetState()
        return true
    }

    private func updateProjectDisplayOrder(placement: ActiveProjectDropPlacement) {
        guard let draggingProjectId else { return }
        let scope = ArchiveOrderScope.parent(targetFolder)
        let naturalIDs = allProjects
            .filter { candidate in
                candidate.isArchived
                    && candidate.archiveFolder?.folderId == targetFolder?.folderId
            }
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(\.projectId)
        var ids = projectDisplayOrderByFolder[scope] ?? naturalIDs
        guard let sourceIndex = ids.firstIndex(of: draggingProjectId),
              let targetIndex = ids.firstIndex(of: targetProject.projectId)
        else { return }
        let destination = placement == .after ? targetIndex + 1 : targetIndex
        ids.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        withAnimation(.easeInOut(duration: 0.12)) {
            projectDisplayOrderByFolder[scope] = ids
        }
    }

    private func persistProjectDisplayOrder(in folder: ArchiveFolder?, service: ProjectService) -> Bool {
        let scope = ArchiveOrderScope.parent(folder)
        guard let orderedIDs = projectDisplayOrderByFolder[scope] else { return false }
        var projectsByID = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.projectId, $0) })
        let orderedProjects = orderedIDs.compactMap { projectsByID.removeValue(forKey: $0) }
        guard !orderedProjects.isEmpty else { return false }
        for (index, project) in orderedProjects.enumerated() {
            project.orderIndex = index
        }
        service.save()
        return true
    }

    private func projectPlacement(for info: DropInfo) -> ActiveProjectDropPlacement {
        info.location.y < ArchiveTreeMetrics.rowHeight / 2 ? .before : .after
    }

    private func clearTargets() {
        activeProjectDropTarget = nil
        archiveFolderDropTarget = nil
        archiveProjectDropTargetFolderId = nil
        archiveProjectDropTarget = nil
    }

    private func resetState() {
        draggingProjectId = nil
        clearTargets()
        projectDisplayOrderByFolder.removeAll()
    }
}

private struct ArchiveRootDropDelegate: DropDelegate {
    let allProjects: [Project]
    let allFolders: [ArchiveFolder]
    let rootArchivedProjects: [Project]
    weak var service: ProjectService?
    @Binding var isArchiveExpanded: Bool
    @Binding var isHighlighted: Bool
    @Binding var folderDisplayOrderByParent: [ArchiveOrderScope: [UUID]]
    @Binding var projectDisplayOrderByFolder: [ArchiveOrderScope: [UUID]]
    @Binding var draggingProjectId: UUID?
    @Binding var draggingFolderId: UUID?
    @Binding var activeProjectDropTarget: ActiveProjectDropTarget?
    @Binding var archiveFolderDropTarget: ArchiveFolderDropTarget?
    @Binding var archiveProjectDropTargetFolderId: UUID?
    @Binding var archiveProjectDropTarget: ArchiveProjectDropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        return draggingProjectId != nil || draggingFolderId != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        clearDropTargets()
        guard draggingProjectId != nil || draggingFolderId != nil else {
            isHighlighted = false
            return nil
        }
        isHighlighted = true
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isHighlighted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let service else {
            resetDragState()
            return false
        }

        if let draggingFolderId,
           let folder = allFolders.first(where: { $0.folderId == draggingFolderId }) {
            service.moveFolder(folder, to: nil)
            withAnimation(.easeInOut(duration: 0.15)) {
                isArchiveExpanded = true
            }
            resetDragState()
            return true
        }

        if let draggingProjectId,
           let project = allProjects.first(where: { $0.projectId == draggingProjectId }) {
            service.moveProjectToArchiveRoot(project, toOffset: rootArchivedProjects.count)
            withAnimation(.easeInOut(duration: 0.15)) {
                isArchiveExpanded = true
            }
            resetDragState()
            return true
        }

        resetDragState()
        return false
    }

    private func clearDropTargets() {
        activeProjectDropTarget = nil
        archiveFolderDropTarget = nil
        archiveProjectDropTargetFolderId = nil
        archiveProjectDropTarget = nil
        isHighlighted = false
        folderDisplayOrderByParent.removeAll()
        projectDisplayOrderByFolder.removeAll()
    }

    private func resetDragState() {
        draggingProjectId = nil
        draggingFolderId = nil
        clearDropTargets()
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
    /// 项目未选中时的进度条填充色（浅色/深色模式在此处调整）
    static let progressUnselectedFillColor = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.30, alpha: 0.88)
            : NSColor(calibratedWhite: 0.78, alpha: 0.6)
    })
    static let projectIconContainerSize: CGFloat = 24
    static let projectIconRingLineWidth: CGFloat = 2
    static let projectIconFont = Font.caption
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
    static let projectRowSpacing: CGFloat = 8
    static let projectDropLineGapOffset: CGFloat = 5
    static let projectReorderPersistDelay: Double = 0.45
    static let projectTitleFont = Font.callout
    static let shadowAnimationDuration: Double = 0.15
    static let shadowAnimation = Animation.easeInOut(duration: shadowAnimationDuration)
    static let selectionAnimation = Animation.easeInOut(duration: shadowAnimationDuration)
}

struct ActiveProjectRow: View {
    let project: Project
    let isSelected: Bool
    var highlightRequestID: UUID? = nil
    let isFavoriteForContext: () -> Bool
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    /// 项目行强调色：100% 完成时使用成功色，否则使用项目自定义主题色
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

    private var capsuleBackgroundColor: Color {
        if isSelected {
            return accentColor
        }
        if isHovered {
            return ActiveProjectRowMetrics.sidebarHoverColor
        }
        return ActiveProjectRowMetrics.progressTrackColor
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

    private func projectIcon(
        symbolColor: Color,
        backgroundColor: Color,
        ringColor: Color
    ) -> some View {
        ZStack {
            Circle()
                .fill(backgroundColor)

            Image(systemName: project.sfSymbolName)
                .font(ActiveProjectRowMetrics.projectIconFont)
                .foregroundStyle(symbolColor)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, project.progress))))
                .stroke(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: ActiveProjectRowMetrics.projectIconRingLineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(
            width: ActiveProjectRowMetrics.projectIconContainerSize,
            height: ActiveProjectRowMetrics.projectIconContainerSize
        )
    }

    /// 公共内容行
    private func rowContent(
        contentColor: Color,
        iconSymbolColor: Color,
        iconBackgroundColor: Color,
        iconRingColor: Color,
        reminderColor: Color,
        favoriteColor: Color
    ) -> some View {
        HStack(spacing: 8) {
            projectIcon(
                symbolColor: iconSymbolColor,
                backgroundColor: iconBackgroundColor,
                ringColor: iconRingColor
            )
            .padding(.leading, -4)

            Text(project.title)
                .font(ActiveProjectRowMetrics.projectTitleFont)
                .foregroundStyle(contentColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if hasScheduledProjectReminder {
                    Image(systemName: "alarm.fill")
                        .font(.caption)
                        .foregroundStyle(reminderColor)
                        .frame(width: 16)
                }
                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(favoriteColor)
                        .frame(width: 16)
                }
            }
        }
        .padding(.horizontal, 8)
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

            // 胶囊底色
            if isSelected || isHovered {
                Capsule(style: .continuous)
                    .fill(capsuleBackgroundColor)
                    .frame(height: progressBarHeight)
            } else {
                LightGlassView()
                    .clipShape(Capsule(style: .continuous))
                    .frame(height: progressBarHeight)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [
                                            Color.white.opacity(0.22),
                                            Color.white.opacity(0.08),
                                            Color.white.opacity(0.02),
                                            Color.white.opacity(0.04),
                                        ]
                                        : [
                                            Color.white.opacity(0.55),
                                            Color.white.opacity(0.18),
                                            Color.black.opacity(0.06),
                                            Color.black.opacity(0.10),
                                        ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: colorScheme == .dark ? 0.8 : 0.6
                            )
                    )
            }

            if isSelected {
                rowContent(
                    contentColor: .white,
                    iconSymbolColor: .white,
                    iconBackgroundColor: accentColor,
                    iconRingColor: .white,
                    reminderColor: .white,
                    favoriteColor: .white
                )
            } else {
                rowContent(
                    contentColor: .primary,
                    iconSymbolColor: accentColor,
                    iconBackgroundColor: ActiveProjectRowMetrics.progressUnselectedFillColor,
                    iconRingColor: accentColor,
                    reminderColor: .orange,
                    favoriteColor: ViabarColor.warning
                )
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
        .background {
            SidebarRightClickMenu(source: "activeProject:\(project.title)") {
                [
                    .item(isFavoriteForContext() ? "取消收藏" : "收藏", systemImage: isFavoriteForContext() ? "star.slash" : "star", action: onToggleFavorite),
                    .item("编辑", systemImage: "pencil", action: onEdit),
                    .item("归档", systemImage: "archivebox", action: onArchive),
                    .separator,
                    .item("删除", systemImage: "trash", action: onDelete)
                ]
            } onRightClick: {
                sidebarContextLog("row rightClick activeProject title=\(project.title) id=\(project.projectId)")
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

private struct ActiveProjectDropOverlay: View {
    let projects: [Project]
    let selectedProjectId: UUID?
    let draggingProjectId: UUID?
    weak var service: ProjectService?
    @Binding var draggingProjectIdBinding: UUID?
    @Binding var dropTarget: ActiveProjectDropTarget?
    @Binding var displayOrderOverride: [UUID]?
    @Binding var isCommittingDrop: Bool

    private var isDraggingActiveProject: Bool {
        guard let draggingProjectId else { return false }
        return projects.contains { $0.projectId == draggingProjectId }
    }

    var body: some View {
        GeometryReader { proxy in
            let zones = dropZones(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(zones) { zone in
                    ActiveProjectDropHitRegion()
                        .frame(width: proxy.size.width, height: max(zone.rect.height, 1))
                        .position(x: proxy.size.width / 2, y: zone.rect.midY)
                        .allowsHitTesting(false)
                }

                Color.primary.opacity(0.001)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [.plainText],
                        delegate: ActiveProjectOverlayDropDelegate(
                            zones: zones,
                            activeProjects: projects,
                            service: service,
                            draggingProjectId: $draggingProjectIdBinding,
                            dropTarget: $dropTarget,
                            displayOrderOverride: $displayOrderOverride,
                            isCommittingDrop: $isCommittingDrop
                        )
                    )
            }
            .allowsHitTesting(isDraggingActiveProject)
        }
    }

    private func dropZones(width: CGFloat) -> [ActiveProjectDropZone] {
        let rows = projectRows(width: width)
        guard !rows.isEmpty else { return [] }

        var zones: [ActiveProjectDropZone] = []

        if let first = rows.first {
            zones.append(
                ActiveProjectDropZone(
                    id: "before-\(first.project.projectId.uuidString)",
                    targetProject: first.project,
                    placement: .before,
                    target: ActiveProjectDropTarget(projectId: first.project.projectId, placement: .before),
                    rect: CGRect(
                        x: first.frame.minX,
                        y: first.frame.minY,
                        width: first.frame.width,
                        height: first.frame.height / 2
                    ),
                    lineY: first.frame.minY
                )
            )
        }

        for index in rows.indices {
            let row = rows[index]
            let nextRow = index < rows.count - 1 ? rows[index + 1] : nil
            let targetProject = nextRow?.project ?? row.project
            let placement: ActiveProjectDropPlacement = nextRow == nil ? .after : .before
            let lowerBound = row.frame.midY
            let upperBound = nextRow?.frame.midY ?? row.frame.maxY
            let lineY = nextRow.map { (row.frame.maxY + $0.frame.minY) / 2 } ?? row.frame.maxY

            zones.append(
                ActiveProjectDropZone(
                    id: "\(row.project.projectId.uuidString)-boundary",
                    targetProject: targetProject,
                    placement: placement,
                    target: ActiveProjectDropTarget(projectId: targetProject.projectId, placement: placement),
                    rect: CGRect(
                        x: row.frame.minX,
                        y: lowerBound,
                        width: row.frame.width,
                        height: max(upperBound - lowerBound, 1)
                    ),
                    lineY: lineY
                )
            )
        }

        return zones
    }

    private func projectRows(width: CGFloat) -> [ActiveProjectDropRow] {
        var y: CGFloat = 0

        return projects.map { project in
            let height = rowHeight(for: project)
            let row = ActiveProjectDropRow(
                project: project,
                frame: CGRect(x: 0, y: y, width: width, height: height)
            )
            y += height + ActiveProjectRowMetrics.projectRowSpacing
            return row
        }
    }

    private func rowHeight(for project: Project) -> CGFloat {
        if project.projectId == selectedProjectId {
            return ActiveProjectRowMetrics.selectedRowHeight
                + ActiveProjectRowMetrics.selectedShadowBleed * 2
        }

        return ActiveProjectRowMetrics.defaultRowHeight
    }
}

private struct ActiveProjectDropHitRegion: View {
    var body: some View {
        Color.primary.opacity(0.001)
            .contentShape(Rectangle())
    }
}

private struct ActiveProjectDropRow {
    let project: Project
    let frame: CGRect
}

private struct ActiveProjectDropZone: Identifiable {
    let id: String
    let targetProject: Project
    let placement: ActiveProjectDropPlacement
    let target: ActiveProjectDropTarget
    let rect: CGRect
    let lineY: CGFloat
}

private struct ActiveProjectOverlayDropDelegate: DropDelegate {
    let zones: [ActiveProjectDropZone]
    let activeProjects: [Project]
    weak var service: ProjectService?
    @Binding var draggingProjectId: UUID?
    @Binding var dropTarget: ActiveProjectDropTarget?
    @Binding var displayOrderOverride: [UUID]?
    @Binding var isCommittingDrop: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else {
            projectDropLog("validate=false reason=no plainText")
            return false
        }
        guard let draggingProjectId else {
            projectDropLog("validate=false reason=no draggingProjectId")
            return false
        }
        let isValid = activeProjects.contains { $0.projectId == draggingProjectId }
        if !isValid {
            projectDropLog("validate=false reason=dragging id not active id=\(draggingProjectId)")
        }
        return isValid
    }

    func dropEntered(info: DropInfo) {
        projectDropLog("dropEntered y=\(info.location.y)")
        updateDisplayOrder(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingProjectId != nil else {
            dropTarget = nil
            projectDropLog("dropUpdated proposal=nil reason=no draggingProjectId")
            return nil
        }
        updateDisplayOrder(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        projectDropLog("dropExited reset display order y=\(info.location.y)")
        restoreDisplayOrder()
    }

    func performDrop(info: DropInfo) -> Bool {
        projectDropLog("performDrop begin y=\(info.location.y)")
        updateDisplayOrder(info: info)

        guard let service else {
            projectDropLog("performDrop=false reason=missing service")
            resetDragState(restoresDisplayOrder: true)
            return false
        }

        let finalProjects = finalDisplayProjects()
        isCommittingDrop = true
        resetDragState(restoresDisplayOrder: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + ActiveProjectRowMetrics.projectReorderPersistDelay) {
            projectDropLog("performDrop persist begin")
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                for (index, project) in finalProjects.enumerated() where project.orderIndex != index {
                    project.orderIndex = index
                }
            }
            service.save()
            projectDropLog("performDrop persist end")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                projectDropLog("performDrop clear display order override")
                displayOrderOverride = nil
                isCommittingDrop = false
            }
        }
        return true
    }

    private func updateDisplayOrder(info: DropInfo) {
        let currentDraggingProjectId = draggingProjectId
        guard let draggingProjectId = currentDraggingProjectId,
              let zone = zone(for: info),
              draggingProjectId != zone.targetProject.projectId,
              let sourceIndex = activeProjects.firstIndex(where: { $0.projectId == draggingProjectId }),
              let targetIndex = activeProjects.firstIndex(where: { $0.projectId == zone.targetProject.projectId })
        else {
            dropTarget = nil
            return
        }

        let destination = moveDestination(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            placement: zone.placement
        )
        guard sourceIndex != destination else {
            dropTarget = nil
            return
        }

        var reorderedProjects = activeProjects
        reorderedProjects.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        let reorderedIDs = reorderedProjects.map(\.projectId)
        guard displayOrderOverride != reorderedIDs else { return }

        projectDropLog("update display order source=\(sourceIndex) target=\(targetIndex) destination=\(destination) placement=\(String(describing: zone.placement)) y=\(info.location.y)")
        withAnimation(.easeInOut(duration: 0.12)) {
            displayOrderOverride = reorderedIDs
        }
        dropTarget = nil
    }

    private func finalDisplayProjects() -> [Project] {
        guard let displayOrderOverride else {
            return activeProjects
        }

        var projectsByID = Dictionary(uniqueKeysWithValues: activeProjects.map { ($0.projectId, $0) })
        var finalProjects = displayOrderOverride.compactMap { projectsByID.removeValue(forKey: $0) }
        finalProjects.append(contentsOf: activeProjects.filter { projectsByID[$0.projectId] != nil })
        return finalProjects
    }

    private func moveDestination(
        sourceIndex: Int,
        targetIndex: Int,
        placement: ActiveProjectDropPlacement
    ) -> Int {
        switch placement {
        case .before:
            if sourceIndex < targetIndex {
                return targetIndex == sourceIndex + 1 ? targetIndex + 1 : targetIndex
            }
            return targetIndex
        case .after:
            return targetIndex + 1
        }
    }

    private func zone(for info: DropInfo) -> ActiveProjectDropZone? {
        zones.first { zone in
            zone.rect.minY <= info.location.y && info.location.y <= zone.rect.maxY
        }
    }

    private func resetDragState(restoresDisplayOrder: Bool) {
        projectDropLog("reset state begin")
        draggingProjectId = nil
        dropTarget = nil
        if restoresDisplayOrder {
            displayOrderOverride = nil
            isCommittingDrop = false
        }
        projectDropLog("reset state end")
    }

    private func restoreDisplayOrder() {
        dropTarget = nil
        displayOrderOverride = nil
        isCommittingDrop = false
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
                    ArchivedProjectSelectableRow(
                        project: project,
                        level: level,
                        indentPerLevel: indentPerLevel,
                        isSelected: selection == .project(project),
                        highlightRequestID: projectHighlightRequestID(for: project),
                        showsTopDropLine: index == 0 && archiveProjectDropTarget == ArchiveProjectDropTarget(projectId: project.projectId, placement: .before),
                        showsBottomDropLine: archiveProjectDropTarget == ArchiveProjectDropTarget(projectId: project.projectId, placement: .after)
                            || (index < sortedProjects.count - 1
                                && archiveProjectDropTarget == ArchiveProjectDropTarget(projectId: sortedProjects[index + 1].projectId, placement: .before)),
                        onDragStart: { draggingActiveProjectId = project.projectId },
                        onContextTarget: {},
                        onUnarchive: { service?.unarchiveProject(project) },
                        onDelete: { onDeleteProject(project) }
                    ) {
                        selection = .project(project)
                    }
                    .onDrop(
                        of: [.plainText],
                        delegate: ArchiveProjectReorderDropDelegate(
                            targetProject: project,
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
    let showsTopDropLine: Bool
    let showsBottomDropLine: Bool
    let onDragStart: () -> Void
    let onContextTarget: () -> Void
    let onUnarchive: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

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
            Spacer().frame(width: indentPerLevel * CGFloat(max(level, 0)))

            Spacer()
                .frame(width: 8)

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
                if !isSelected && !isHovered {
                    LightGlassView()
                        .clipShape(Capsule(style: .continuous))
                        .frame(height: progressBarHeight)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [
                                                Color.white.opacity(0.22),
                                                Color.white.opacity(0.08),
                                                Color.white.opacity(0.02),
                                                Color.white.opacity(0.04),
                                            ]
                                            : [
                                                Color.white.opacity(0.55),
                                                Color.white.opacity(0.18),
                                                Color.black.opacity(0.06),
                                                Color.black.opacity(0.10),
                                            ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: colorScheme == .dark ? 0.8 : 0.6
                                )
                        )
                }
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
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                onContextTarget()
            }
        }
        .searchTargetHighlight(
            triggerID: highlightRequestID,
            isActive: highlightRequestID != nil,
            cornerRadius: rowHeight / 2
        )
        .padding(.vertical, 0)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .overlay(alignment: .top) {
            if showsTopDropLine {
                ActiveProjectDropIndicator()
                    .offset(y: -ActiveProjectRowMetrics.projectDropLineGapOffset)
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomDropLine {
                ActiveProjectDropIndicator()
                    .offset(y: ActiveProjectRowMetrics.projectDropLineGapOffset)
            }
        }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: project.projectId.uuidString as NSString)
        }
        .background {
            SidebarRightClickMenu(source: "archivedProject:\(project.title)") {
                [
                    .item("取消归档", systemImage: "arrow.uturn.backward", action: onUnarchive),
                    .separator,
                    .item("删除项目", systemImage: "trash", action: onDelete)
                ]
            } onRightClick: {
                onContextTarget()
                sidebarContextLog("row rightClick archivedProject title=\(project.title) id=\(project.projectId)")
            }
        }
    }
}

// MARK: - ArchiveProjectReorderDropDelegate

struct ArchiveProjectReorderDropDelegate: DropDelegate {
    let targetProject: Project
    let folder: ArchiveFolder
    let folderProjects: [Project]
    weak var service: ProjectService?
    @Binding var draggingProjectId: UUID?
    @Binding var dropTarget: ArchiveProjectDropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.plainText]) else { return false }
        guard let draggingProjectId else { return false }
        return draggingProjectId != targetProject.projectId
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        guard draggingProjectId != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}

    func performDrop(info: DropInfo) -> Bool {
        guard let service,
              let draggingProjectId,
              let sourceIndex = folderProjects.firstIndex(where: { $0.projectId == draggingProjectId }),
              let targetIndex = folderProjects.firstIndex(where: { $0.projectId == targetProject.projectId }),
              sourceIndex != targetIndex
        else {
            resetDragState()
            return false
        }

        let placement = dropTarget?.placement ?? placement(for: info)
        let destination = moveDestination(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            placement: placement
        )

        guard sourceIndex != destination else {
            resetDragState()
            return false
        }

        service.reorderFolderProjects(folder, fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        resetDragState()
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard let draggingProjectId, draggingProjectId != targetProject.projectId else {
            dropTarget = nil
            return
        }

        dropTarget = ArchiveProjectDropTarget(
            projectId: targetProject.projectId,
            placement: placement(for: info)
        )
    }

    private func placement(for info: DropInfo) -> ActiveProjectDropPlacement {
        info.location.y < 15 ? .before : .after
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

    private func resetDragState() {
        draggingProjectId = nil
        dropTarget = nil
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
