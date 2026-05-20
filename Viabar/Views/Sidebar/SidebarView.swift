import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

    var title: String {
        switch self {
        case .createRoot:
            return "新建文件夹"
        case .createChild:
            return "新建子文件夹"
        case .rename:
            return "重命名文件夹"
        }
    }

    var message: String {
        switch self {
        case .createRoot:
            return "输入归档文件夹名称。"
        case .createChild(let folder):
            return "在“\(folder.name)”下创建子文件夹。"
        case .rename:
            return "输入新的文件夹名称。"
        }
    }

    var confirmTitle: String {
        switch self {
        case .rename:
            return "重命名"
        default:
            return "创建"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Environment(ServiceContainer.self) private var container
    @Query(sort: \Project.orderIndex) private var allProjects: [Project]
    @Query(sort: \ArchiveFolder.orderIndex) private var allFolders: [ArchiveFolder]
    @Binding var selection: SidebarSelection?

    @State private var showNewProjectSheet: Bool = false
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
        List(selection: $selection) {
            overviewSection
            projectsSection
            archiveSection
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectView()
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
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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
            Label {
                Text("总览")
            } icon: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.blue)
            }
            .tag(SidebarSelection.overview)
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
                ForEach(activeProjects) { project in
                    ActiveProjectRow(
                        project: project,
                        onArchive: { archivePickerProject = project },
                        onSelect: {
                            print("[SidebarView] selection → \(project.title)")
                            selection = .project(project)
                        }
                    )
                    .tag(SidebarSelection.project(project))
                    .overlay(alignment: .top) {
                        if activeProjectDropTarget == ActiveProjectDropTarget(projectId: project.projectId, placement: .before) {
                            ActiveProjectDropIndicator()
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if activeProjectDropTarget == ActiveProjectDropTarget(projectId: project.projectId, placement: .after) {
                            ActiveProjectDropIndicator()
                        }
                    }
                    .onDrag {
                        draggingActiveProjectId = project.projectId
                        let provider = NSItemProvider(object: project.projectId.uuidString as NSString)
                        return provider
                    }
                    .onDrop(
                        of: [.plainText],
                        delegate: ActiveProjectReorderDropDelegate(
                            targetProject: project,
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
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showNewProjectSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("新建项目")
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
                        .font(.headline)
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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("新建文件夹")
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
                    onDeleteFolder: { projectService?.deleteArchiveFolder($0) }
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

}

// MARK: - ActiveProjectRow

struct ActiveProjectRow: View {
    let project: Project
    let onArchive: () -> Void
    let onSelect: () -> Void

    @Environment(ServiceContainer.self) private var container

    private var projectService: ProjectService? {
        container.projectService
    }

    /// 填充色：100% → success，否则 → 项目自定义主题色
    private var accentColor: Color {
        project.progress >= 1.0
            ? ViabarColor.success
            : Color(hex: project.accentColor)
    }

    /// 公共内容行，供双层渲染复用
    private func rowContent(color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: project.sfSymbolName)
                .font(.title3)
            Text(project.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Int(project.progress * 100))%")
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // 轨道底色
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary.opacity(0.45))

            // 进度填充
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(accentColor.opacity(0.88))
                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(project.progress))))
            }

            // 深色文字层
            rowContent(color: .primary)

            // 白色文字层
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
        .frame(height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onTapGesture {
            print("[ActiveProjectRow] 点击选中: \(project.title)")
            onSelect()
        }
        .contextMenu {
            Button { onArchive() } label: {
                Label("归档…", systemImage: "archivebox")
            }
            Divider()
            Button("删除项目", role: .destructive) {
                projectService?.deleteProject(project)
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

struct ActiveProjectReorderDropDelegate: DropDelegate {
    let targetProject: Project
    let activeProjects: [Project]
    weak var service: ProjectService?
    @Binding var draggingProjectId: UUID?
    @Binding var dropTarget: ActiveProjectDropTarget?

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

    func dropExited(info: DropInfo) {
        if dropTarget?.projectId == targetProject.projectId {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingProjectId != nil else {
            resetDragState()
            return false
        }

        guard let service else {
            resetDragState()
            return false
        }

        loadProjectId(from: info) { draggedId in
            guard let draggedId,
                  let sourceIndex = activeProjects.firstIndex(where: { $0.projectId == draggedId }),
                  let targetIndex = activeProjects.firstIndex(where: { $0.projectId == targetProject.projectId }),
                  sourceIndex != targetIndex
            else {
                resetDragState()
                return
            }

            let placement = dropTarget?.placement ?? placement(for: info)
            let destination = targetIndex + (placement == .after ? 1 : 0)

            guard sourceIndex != destination else {
                resetDragState()
                return
            }

            service.reorderActiveProjects(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
            resetDragState()
        }

        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard let draggingProjectId, draggingProjectId != targetProject.projectId else {
            dropTarget = nil
            return
        }

        dropTarget = ActiveProjectDropTarget(
            projectId: targetProject.projectId,
            placement: placement(for: info)
        )
    }

    private func placement(for info: DropInfo) -> ActiveProjectDropPlacement {
        info.location.y < 19 ? .before : .after
    }

    private func loadProjectId(from info: DropInfo, completion: @escaping (UUID?) -> Void) {
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            completion(draggingProjectId)
            return
        }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            let uuid = (item as? String).flatMap(UUID.init(uuidString:))
            DispatchQueue.main.async {
                completion(uuid ?? draggingProjectId)
            }
        }
    }

    private func resetDragState() {
        draggingProjectId = nil
        dropTarget = nil
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
                    onDeleteFolder: onDeleteFolder
                )
            }

            // 项目列表
            if sortedProjects.isEmpty {
                EmptyView()
            } else {
                ForEach(sortedProjects) { project in
                    ArchivedProjectSelectableRow(
                        project: project,
                        level: level,
                        indentPerLevel: indentPerLevel,
                        isSelected: selection == .project(project),
                        dropTarget: archiveProjectDropTarget,
                        onDragStart: { draggingActiveProjectId = project.projectId }
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
    let dropTarget: ArchiveProjectDropTarget?
    let onDragStart: () -> Void
    let onSelect: () -> Void

    @Environment(ServiceContainer.self) private var container

    private var projectService: ProjectService? {
        container.projectService
    }

    private var accentColor: Color {
        project.progress >= 1.0
            ? ViabarColor.success
            : Color(hex: project.accentColor)
    }

    private func rowContent(color: Color, usesProjectIconColor: Bool = false) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: indentPerLevel * CGFloat(level + 1) + 5)

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
            print("[ArchivedProjectSelectableRow] 点击选中: \(project.title)")
            onSelect()
        } label: {
            Group {
                if isSelected {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.quaternary.opacity(0.45))

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(accentColor.opacity(0.88))
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(project.progress))))
                        }

                        rowContent(color: .primary)

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
                    .frame(height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    rowContent(color: .secondary, usesProjectIconColor: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 0)
        .overlay(alignment: .top) {
            if dropTarget == ArchiveProjectDropTarget(projectId: project.projectId, placement: .before) {
                ActiveProjectDropIndicator()
            }
        }
        .overlay(alignment: .bottom) {
            if dropTarget == ArchiveProjectDropTarget(projectId: project.projectId, placement: .after) {
                ActiveProjectDropIndicator()
            }
        }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: project.projectId.uuidString as NSString)
        }
        .contextMenu {
            Button("取消归档") {
                projectService?.unarchiveProject(project)
            }
            Divider()
            Button("删除项目", role: .destructive) {
                projectService?.deleteProject(project)
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

    func dropExited(info: DropInfo) {
        if dropTarget?.projectId == targetProject.projectId {
            dropTarget = nil
        }
    }

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
    let message: String
    let action: String
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

#Preview {
    @Previewable @State var selection: SidebarSelection? = .overview

    NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        Text("Detail")
    }
    .environment(ServiceContainer())
    .modelContainer(for: Project.self, inMemory: true)
}
