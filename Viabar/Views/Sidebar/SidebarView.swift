import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case overview
    case project(Project)
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
                    .onDrag {
                        NSItemProvider(object: project.projectId.uuidString as NSString)
                    }
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
                // 展开区顶部：新建文件夹入口
                Button {
                    projectService?.createArchiveFolder(name: "新文件夹")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        Text("新建文件夹")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)

                archiveContent
            }
        } header: {
            HStack {
                Image(systemName: isArchiveExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("归档")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isArchiveExpanded.toggle()
                }
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
                onAction: { projectService?.createArchiveFolder(name: "默认归档") }
            )
        } else {
            ForEach(rootFolders) { folder in
                RecursiveFolderRow(
                    folder: folder,
                    selection: $selection,
                    level: 0,
                    expandedFolderIds: $expandedFolderIds,
                    allProjects: allProjects,
                    service: projectService
                )
            }
            .onMove { offsets, target in
                projectService?.reorderFolders(fromOffsets: offsets, toOffset: target)
            }
        }
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

// MARK: - RecursiveFolderRow

/// 递归文件夹行 —— 支持无限嵌套级连目录树。
/// 每一层都是独立的 List 行，自带展开/折叠、拖放接收、项目列表。
struct RecursiveFolderRow: View {
    let folder: ArchiveFolder
    @Binding var selection: SidebarSelection?
    let level: Int
    @Binding var expandedFolderIds: Set<UUID>
    let allProjects: [Project]
    weak var service: ProjectService?

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
            allProjects: allProjects
        )

        if isExpanded {
            // 子文件夹（递归）
            ForEach(sortedChildren) { child in
                RecursiveFolderRow(
                    folder: child,
                    selection: $selection,
                    level: level + 1,
                    expandedFolderIds: $expandedFolderIds,
                    allProjects: allProjects,
                    service: service
                )
            }

            // 项目列表
            if sortedProjects.isEmpty {
                HStack(spacing: 0) {
                    Spacer().frame(width: indentPerLevel * CGFloat(level + 1) + 44)
                    Text("拖拽项目到此处")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(sortedProjects) { project in
                    ArchivedProjectSelectableRow(
                        project: project,
                        level: level,
                        indentPerLevel: indentPerLevel
                    ) {
                        selection = .project(project)
                    }
                    .onDrag {
                        NSItemProvider(object: project.projectId.uuidString as NSString)
                    }
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

    private var sortedProjects: [Project] {
        folder.projects.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        HStack(spacing: 6) {
            if level > 0 {
                Spacer().frame(width: 16 * CGFloat(level))
            }

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(ViabarColor.primary)
                .font(.title3)

            Text(folder.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if !sortedProjects.isEmpty {
                Text("\(sortedProjects.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onDrop(
            of: [.plainText],
            delegate: FolderDropDelegate(
                folder: folder,
                service: service,
                allProjects: allProjects
            )
        )
        .contextMenu {
            Button("新建子文件夹") {
                service?.createArchiveFolder(name: "子文件夹", parent: folder)
            }
            Divider()
            Button("删除文件夹", role: .destructive) {
                service?.deleteArchiveFolder(folder)
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
    let onSelect: () -> Void

    @Environment(ServiceContainer.self) private var container

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Spacer().frame(width: indentPerLevel * CGFloat(level + 1) + 28)
                Image(systemName: "archivebox")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text(project.title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
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

// MARK: - FolderDropDelegate

struct FolderDropDelegate: DropDelegate {
    let folder: ArchiveFolder
    weak var service: ProjectService?
    let allProjects: [Project]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let svc = service else { return false }

        let providers = info.itemProviders(for: [.plainText])
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let uuidString = item as? String,
                      let uuid = UUID(uuidString: uuidString),
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
