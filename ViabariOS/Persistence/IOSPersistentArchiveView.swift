import SwiftUI

private enum IOSPersistentArchiveComposerSession: Equatable {
    case createRoot
    case createChild(parentID: UUID)
    case rename(folderID: UUID)
}

struct IOSPersistentArchiveView: View {
    @Environment(ServiceContainer.self) private var services
    @Bindable var coordinator: IOSPersistenceCoordinator
    let projects: [Project]
    let archiveFolders: [ArchiveFolder]
    let rootFolderCreationTrigger: UUID?
    @Binding var isComposerPresented: Bool

    @State private var composerSession: IOSPersistentArchiveComposerSession?
    @State private var composerText = ""
    @State private var folderPendingDeletionID: UUID?
    @State private var projectPendingDeletionID: UUID?
    @State private var projectAwaitingFinalDeletionID: UUID?
    @State private var movingProject: Project?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    IOSPrototypeSectionLabel(title: "归档项目")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootFolders, id: \.folderId) { folder in
                            IOSPersistentArchiveFolderNodeView(
                                coordinator: coordinator,
                                folder: folder,
                                level: 0,
                                onCreateChild: beginCreatingChild,
                                onRename: beginRenaming,
                                onDeleteFolder: requestFolderDeletion,
                                onMoveProject: { movingProject = $0 },
                                onDeleteProject: { projectPendingDeletionID = $0 }
                            )
                        }
                    }
                    .iosPrototypeCardSurface(cornerRadius: 14)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 150)
            }

            if let composerSession {
                HStack(spacing: 10) {
                    IOSPrototypeDetailComposer(text: $composerText, placeholder: composerPlaceholder(composerSession))
                    IOSPrototypeDetachedActionButton(symbol: "paperplane.fill") {
                        saveComposer(composerSession)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
        .onChange(of: rootFolderCreationTrigger) { _, trigger in
            guard trigger != nil else { return }
            composerText = ""
            composerSession = .createRoot
            isComposerPresented = true
        }
        .sheet(item: $movingProject) { project in
            IOSPersistentArchiveFolderPicker(
                folders: archiveFolders,
                currentFolderID: project.archiveFolder?.folderId,
                actionTitle: "移动"
            ) { folder in
                services.projectService?.moveProjectToFolder(project, folder: folder)
            }
        }
        .alert("删除非空文件夹？", isPresented: folderDeletionConfirmation) {
            Button("确认删除", role: .destructive) {
                guard let folderPendingDeletionID,
                      let folder = archiveFolders.first(where: { $0.folderId == folderPendingDeletionID })
                else { return }
                services.projectService?.deleteArchiveFolder(folder)
                self.folderPendingDeletionID = nil
            }
            Button("取消", role: .cancel) {
                folderPendingDeletionID = nil
            }
        } message: {
            Text("文件夹内包含子文件夹或归档项目。删除后不可恢复。")
        }
        .alert("删除项目？", isPresented: firstProjectDeletionConfirmation) {
            Button("继续", role: .destructive) {
                projectAwaitingFinalDeletionID = projectPendingDeletionID
                projectPendingDeletionID = nil
            }
            Button("取消", role: .cancel) {
                projectPendingDeletionID = nil
            }
        } message: {
            if let project = pendingDeletionProject {
                Text("“\(project.title)”包含 \(project.milestones.count) 条任务和 \(project.memos.count) 条备忘录。删除项目后不可恢复。")
            }
        }
        .alert("再次确认删除项目", isPresented: finalProjectDeletionConfirmation) {
            Button("确认删除", role: .destructive) {
                guard let projectAwaitingFinalDeletionID,
                      let project = projects.first(where: { $0.projectId == projectAwaitingFinalDeletionID })
                else { return }
                services.projectService?.deleteProject(project)
                self.projectAwaitingFinalDeletionID = nil
            }
            Button("取消", role: .cancel) {
                projectAwaitingFinalDeletionID = nil
            }
        } message: {
            Text("是否确认永久删除这个项目？")
        }
    }

    private var rootFolders: [ArchiveFolder] {
        archiveFolders
            .filter { $0.parent == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func beginCreatingChild(_ folder: ArchiveFolder) {
        composerText = ""
        composerSession = .createChild(parentID: folder.folderId)
        isComposerPresented = true
    }

    private func beginRenaming(_ folder: ArchiveFolder) {
        composerText = folder.name
        composerSession = .rename(folderID: folder.folderId)
        isComposerPresented = true
    }

    private func requestFolderDeletion(_ folder: ArchiveFolder) {
        if !folder.children.isEmpty || !folder.projects.isEmpty {
            folderPendingDeletionID = folder.folderId
        } else {
            services.projectService?.deleteArchiveFolder(folder)
        }
    }

    private func saveComposer(_ session: IOSPersistentArchiveComposerSession) {
        let name = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            closeComposer()
            return
        }
        switch session {
        case .createRoot:
            services.projectService?.createArchiveFolder(name: name)
        case let .createChild(parentID):
            guard let parent = archiveFolders.first(where: { $0.folderId == parentID }) else { break }
            services.projectService?.createArchiveFolder(name: name, parent: parent)
            coordinator.expandedArchiveFolderIDs.insert(parentID)
        case let .rename(folderID):
            guard let folder = archiveFolders.first(where: { $0.folderId == folderID }) else { break }
            folder.name = name
            services.projectService?.save()
        }
        closeComposer()
    }

    private func closeComposer() {
        composerText = ""
        composerSession = nil
        isComposerPresented = false
        dismissIOSPrototypeKeyboard()
    }

    private func composerPlaceholder(_ session: IOSPersistentArchiveComposerSession) -> LocalizedStringKey {
        switch session {
        case .createRoot: "新增根文件夹"
        case .createChild: "新增子文件夹"
        case .rename: "文件夹名称"
        }
    }

    private var pendingDeletionProject: Project? {
        guard let projectPendingDeletionID else { return nil }
        return projects.first { $0.projectId == projectPendingDeletionID }
    }

    private var folderDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { folderPendingDeletionID != nil },
            set: { if !$0 { folderPendingDeletionID = nil } }
        )
    }

    private var firstProjectDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectPendingDeletionID != nil },
            set: { if !$0 { projectPendingDeletionID = nil } }
        )
    }

    private var finalProjectDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectAwaitingFinalDeletionID != nil },
            set: { if !$0 { projectAwaitingFinalDeletionID = nil } }
        )
    }
}

private struct IOSPersistentArchiveFolderNodeView: View {
    @Environment(ServiceContainer.self) private var services
    @Bindable var coordinator: IOSPersistenceCoordinator
    let folder: ArchiveFolder
    let level: Int
    let onCreateChild: (ArchiveFolder) -> Void
    let onRename: (ArchiveFolder) -> Void
    let onDeleteFolder: (ArchiveFolder) -> Void
    let onMoveProject: (Project) -> Void
    let onDeleteProject: (UUID) -> Void

    private var isExpanded: Bool {
        coordinator.expandedArchiveFolderIDs.contains(folder.folderId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderRow

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedChildren, id: \.folderId) { child in
                        IOSPersistentArchiveFolderNodeView(
                            coordinator: coordinator,
                            folder: child,
                            level: level + 1,
                            onCreateChild: onCreateChild,
                            onRename: onRename,
                            onDeleteFolder: onDeleteFolder,
                            onMoveProject: onMoveProject,
                            onDeleteProject: onDeleteProject
                        )
                    }

                    ForEach(sortedProjects, id: \.projectId) { project in
                        archivedProjectRow(project)
                    }
                }
            }
        }
    }

    private var folderRow: some View {
        HStack(spacing: 7) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            Text(folder.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !sortedProjects.isEmpty {
                Text("\(sortedProjects.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, CGFloat(level) * 16)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpanded {
                coordinator.expandedArchiveFolderIDs.remove(folder.folderId)
            } else {
                coordinator.expandedArchiveFolderIDs.insert(folder.folderId)
            }
        }
        .contextMenu {
            Button("新建子文件夹", systemImage: "folder.badge.plus") {
                onCreateChild(folder)
            }
            Button("重命名", systemImage: "pencil") {
                onRename(folder)
            }
            Divider()
            Button("删除文件夹", systemImage: "trash", role: .destructive) {
                onDeleteFolder(folder)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 12 + CGFloat(level) * 16)
        }
    }

    private func archivedProjectRow(_ project: Project) -> some View {
        Button {
            coordinator.selectProject(project)
        } label: {
            HStack(spacing: 7) {
                Color.clear
                    .frame(width: 12)
                Image(systemName: project.sfSymbolName)
                    .foregroundStyle(Color(hex: project.accentColor))
                    .frame(width: 18, alignment: .leading)
                Text(project.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                IOSPrototypeProgressRing(progress: project.progress, size: 20, lineWidth: 4)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .padding(.leading, CGFloat(level + 1) * 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("移动至...", systemImage: "folder") {
                onMoveProject(project)
            }
            Button("取消归档", systemImage: "arrow.uturn.backward") {
                services.projectService?.unarchiveProject(project)
            }
            Divider()
            Button("删除项目", systemImage: "trash", role: .destructive) {
                onDeleteProject(project.projectId)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 12 + CGFloat(level + 1) * 16)
        }
    }

    private var sortedChildren: [ArchiveFolder] {
        folder.children.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var sortedProjects: [Project] {
        folder.projects
            .filter(\.isArchived)
            .sorted { $0.orderIndex < $1.orderIndex }
    }
}
