import SwiftUI

private enum IOSPrototypeArchiveComposerSession: Equatable {
    case createRoot
    case createChild(parentID: UUID)
    case rename(folderID: UUID)
}

struct IOSPrototypeArchiveView: View {
    @Bindable var store: IOSPrototypeStore
    let rootFolderCreationTrigger: UUID?
    @Binding var isComposerPresented: Bool

    @State private var composerSession: IOSPrototypeArchiveComposerSession?
    @State private var composerText = ""
    @State private var folderPendingDeletionID: UUID?
    @State private var projectPendingDeletionID: UUID?
    @State private var projectAwaitingFinalDeletionID: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    IOSPrototypeSectionLabel(title: "归档项目")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.rootArchiveFolders) { folder in
                            IOSPrototypeArchiveFolderNodeView(
                                store: store,
                                folder: folder,
                                level: 0,
                                onCreateChild: beginCreatingChild,
                                onRename: beginRenaming,
                                onDeleteFolder: requestFolderDeletion,
                                onDeleteProject: { projectPendingDeletionID = $0 }
                            )
                        }
                    }
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
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
        .alert("删除非空文件夹？", isPresented: folderDeletionConfirmation) {
            Button("确认删除", role: .destructive) {
                guard let folderPendingDeletionID else { return }
                store.deleteArchiveFolder(folderPendingDeletionID)
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
                guard let projectAwaitingFinalDeletionID else { return }
                store.deleteProject(projectAwaitingFinalDeletionID)
                self.projectAwaitingFinalDeletionID = nil
            }
            Button("取消", role: .cancel) {
                projectAwaitingFinalDeletionID = nil
            }
        } message: {
            Text("是否确认永久删除这个项目？")
        }
    }

    private func beginCreatingChild(_ folderID: UUID) {
        composerText = ""
        composerSession = .createChild(parentID: folderID)
        isComposerPresented = true
    }

    private func beginRenaming(_ folder: IOSPrototypeArchiveFolder) {
        composerText = folder.name
        composerSession = .rename(folderID: folder.id)
        isComposerPresented = true
    }

    private func requestFolderDeletion(_ folderID: UUID) {
        if store.archiveFolderHasContents(folderID) {
            folderPendingDeletionID = folderID
        } else {
            store.deleteArchiveFolder(folderID)
        }
    }

    private func saveComposer(_ session: IOSPrototypeArchiveComposerSession) {
        switch session {
        case .createRoot:
            store.createArchiveFolder(name: composerText)
        case let .createChild(parentID):
            store.createArchiveFolder(name: composerText, parentID: parentID)
            store.expandedArchiveFolderIDs.insert(parentID)
        case let .rename(folderID):
            store.renameArchiveFolder(folderID, name: composerText)
        }
        composerText = ""
        composerSession = nil
        isComposerPresented = false
        dismissIOSPrototypeKeyboard()
    }

    private func composerPlaceholder(_ session: IOSPrototypeArchiveComposerSession) -> LocalizedStringKey {
        switch session {
        case .createRoot:
            return "新增根文件夹"
        case .createChild:
            return "新增子文件夹"
        case .rename:
            return "文件夹名称"
        }
    }

    private var pendingDeletionProject: IOSPrototypeProject? {
        guard let projectPendingDeletionID else { return nil }
        return store.projects.first { $0.id == projectPendingDeletionID }
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

struct IOSPrototypeArchiveFolderNodeView: View {
    @Bindable var store: IOSPrototypeStore
    let folder: IOSPrototypeArchiveFolder
    let level: Int
    let onCreateChild: (UUID) -> Void
    let onRename: (IOSPrototypeArchiveFolder) -> Void
    let onDeleteFolder: (UUID) -> Void
    let onDeleteProject: (UUID) -> Void

    private var isExpanded: Bool {
        store.expandedArchiveFolderIDs.contains(folder.id)
    }

    private var children: [IOSPrototypeArchiveFolder] {
        store.archiveChildren(of: folder.id)
    }

    private var projects: [IOSPrototypeProject] {
        store.archivedProjects(in: folder.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderRow

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(children) { child in
                        IOSPrototypeArchiveFolderNodeView(
                            store: store,
                            folder: child,
                            level: level + 1,
                            onCreateChild: onCreateChild,
                            onRename: onRename,
                            onDeleteFolder: onDeleteFolder,
                            onDeleteProject: onDeleteProject
                        )
                    }

                    ForEach(projects) { project in
                        IOSPrototypeArchivedProjectRow(
                            store: store,
                            projectID: project.id,
                            level: level + 1,
                            onDelete: { onDeleteProject(project.id) }
                        )
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
            Text(folder.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !projects.isEmpty {
                Text("\(projects.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, CGFloat(level) * 16)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpanded {
                store.expandedArchiveFolderIDs.remove(folder.id)
            } else {
                store.expandedArchiveFolderIDs.insert(folder.id)
            }
        }
        .contextMenu {
            Button("新建子文件夹", systemImage: "folder.badge.plus") {
                onCreateChild(folder.id)
            }
            Button("重命名", systemImage: "pencil") {
                onRename(folder)
            }
            Divider()
            Button("删除文件夹", systemImage: "trash", role: .destructive) {
                onDeleteFolder(folder.id)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 12 + CGFloat(level) * 16)
        }
    }
}

struct IOSPrototypeArchivedProjectRow: View {
    @Bindable var store: IOSPrototypeStore
    let projectID: UUID
    let level: Int
    let onDelete: () -> Void

    var body: some View {
        if let project {
            NavigationLink(value: project.id) {
                HStack(spacing: 8) {
                    Image(systemName: project.symbol)
                        .foregroundStyle(Color(prototypeHex: project.accentHex))
                        .frame(width: 18)
                    Text(project.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    IOSPrototypeProgressRing(progress: project.progress, size: 20, lineWidth: 4)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .padding(.leading, CGFloat(level) * 16)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("取消归档", systemImage: "arrow.uturn.backward") {
                    store.unarchive(project.id)
                }
                Divider()
                Button("删除项目", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            }
            .overlay(alignment: .bottom) {
                Divider()
                    .padding(.leading, 12 + CGFloat(level) * 16)
            }
        }
    }

    private var project: IOSPrototypeProject? {
        store.projects.first { $0.id == projectID }
    }
}
