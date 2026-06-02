import SwiftUI

struct IOSPrototypeRootView: View {
    @State private var store = IOSPrototypeStore()

    var body: some View {
        NavigationStack {
            IOSPrototypeHomeView(store: store)
                .navigationDestination(for: UUID.self) { projectID in
                    IOSPrototypeProjectDetailView(store: store, projectID: projectID)
                }
        }
        .onOpenURL { _ in
            // Real Widget deep-link routing will replace this prototype hook.
        }
    }
}

struct IOSPrototypeHomeView: View {
    @Bindable var store: IOSPrototypeStore

    @State private var editingProjectID: UUID?
    @State private var composerText = ""
    @State private var projectPendingDeletionID: UUID?
    @State private var projectAwaitingFinalDeletionID: UUID?
    @State private var isTrashPlaceholderPresented = false
    @State private var archiveRootFolderCreationTrigger: UUID?
    @State private var isArchiveComposerPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissIOSPrototypeKeyboard()
                }

            Group {
                switch store.homeTab {
                case .overview:
                    overview
                case .reports:
                    IOSPlaceholderView(symbol: "checkmark.seal.fill", title: "报告")
                case .archive:
                    IOSPrototypeArchiveView(
                        store: store,
                        rootFolderCreationTrigger: archiveRootFolderCreationTrigger,
                        isComposerPresented: $isArchiveComposerPresented
                    )
                }
            }

            VStack(spacing: 10) {
                if editingProjectID != nil {
                    HStack(spacing: 10) {
                        IOSPrototypeDetailComposer(text: $composerText, placeholder: "项目名称")
                        IOSPrototypeDetachedActionButton(symbol: "paperplane.fill") {
                            saveProjectTitle()
                        }
                    }
                } else if !isArchiveComposerPresented {
                    if store.isSearchPresented {
                        IOSPrototypeSearchView(store: store)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        HStack(spacing: 10) {
                            IOSPrototypeSearchField(store: store)
                            IOSPrototypeDetachedActionButton(symbol: "xmark") {
                                withAnimation(.snappy(duration: 0.22)) {
                                    store.isSearchPresented = false
                                    store.searchText = ""
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            IOSPrototypeHomeTabBar(selection: $store.homeTab)
                                .frame(maxWidth: .infinity)
                            if store.homeTab == .archive {
                                IOSPrototypeDetachedActionButton(symbol: "folder.badge.plus") {
                                    archiveRootFolderCreationTrigger = UUID()
                                }
                            } else {
                                IOSPrototypeDetachedActionButton(symbol: "magnifyingglass") {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        store.isSearchPresented = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $isTrashPlaceholderPresented) {
            IOSPlaceholderView(symbol: "trash", title: "回收站")
                .padding(40)
        }
        .alert("删除项目？", isPresented: firstDeletionConfirmation) {
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
        .alert("再次确认删除项目", isPresented: finalDeletionConfirmation) {
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

    private var overview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    IOSPrototypeCircularIconButton(symbol: "gearshape.fill") {
                    }
                    Spacer()
                    IOSPrototypeCircularIconButton(symbol: "trash") {
                        isTrashPlaceholderPresented = true
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 4)

                if !store.favoriteProjects.isEmpty {
                    IOSPrototypeSectionLabel(title: "星标项目")
                    ForEach(store.favoriteProjects) { project in
                        NavigationLink(value: project.id) {
                            IOSOverviewProjectCard(
                                store: store,
                                project: project,
                                onEdit: { beginEditing(project) },
                                onDelete: { projectPendingDeletionID = project.id }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !store.regularProjects.isEmpty {
                    IOSPrototypeSectionLabel(title: "其他项目")
                        .padding(.top, 4)
                    ForEach(store.regularProjects) { project in
                        NavigationLink(value: project.id) {
                            IOSOverviewProjectCard(
                                store: store,
                                project: project,
                                onEdit: { beginEditing(project) },
                                onDelete: { projectPendingDeletionID = project.id }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 112)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func beginEditing(_ project: IOSPrototypeProject) {
        composerText = project.title
        editingProjectID = project.id
    }

    private func saveProjectTitle() {
        guard let editingProjectID else { return }
        store.renameProject(editingProjectID, title: composerText)
        composerText = ""
        self.editingProjectID = nil
        dismissIOSPrototypeKeyboard()
    }

    private var pendingDeletionProject: IOSPrototypeProject? {
        guard let projectPendingDeletionID else { return nil }
        return store.projects.first { $0.id == projectPendingDeletionID }
    }

    private var firstDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectPendingDeletionID != nil },
            set: { if !$0 { projectPendingDeletionID = nil } }
        )
    }

    private var finalDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectAwaitingFinalDeletionID != nil },
            set: { if !$0 { projectAwaitingFinalDeletionID = nil } }
        )
    }
}

struct IOSOverviewProjectCard: View {
    @Bindable var store: IOSPrototypeStore
    let project: IOSPrototypeProject
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: project.symbol)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                    Text(project.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViabarColor.primary)
                    Spacer()
                    if currentProject.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ViabarColor.warning)
                    }
                }

                Spacer().frame(height: 18)

                if let milestone = project.topUnfinishedMilestone {
                    milestoneRow(milestone.title)
                    if let subtask = milestone.firstUnfinishedSubtask {
                        subtaskRow(subtask.title)
                            .padding(.top, 10)
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    if let reminderDate = project.topUnfinishedMilestone?.reminderDate {
                        Label(reminderDate.formatted(date: .numeric, time: .shortened), systemImage: "alarm.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
                            .padding(.leading, 8)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Text("\(Int(project.progress * 100))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(IOSPrototypeProgressStyle.percentColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 44, alignment: .trailing)
                        IOSPrototypeProgressRing(progress: project.progress)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .frame(height: 150)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("编辑", systemImage: "pencil") {
                onEdit()
            }
            Button("归档", systemImage: "archivebox") {
                store.archive(project.id)
            }
            Button(LocalizedStringKey(currentProject.isFavorite ? "取消收藏" : "收藏"), systemImage: currentProject.isFavorite ? "star.slash" : "star") {
                store.toggleFavorite(project.id)
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
    }

    private var accentColor: Color {
        project.progress >= 1 ? ViabarColor.success : Color(prototypeHex: project.accentHex)
    }

    private var currentProject: IOSPrototypeProject {
        store.projects.first { $0.id == project.id } ?? project
    }

    private func milestoneRow(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 12))
                .foregroundStyle(Color.gray.opacity(0.55))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "#4B5563"))
                .lineLimit(1)
        }
        .padding(.leading, 4)
    }

    private func subtaskRow(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 11))
                .foregroundStyle(Color.gray)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.gray)
                .lineLimit(1)
        }
        .padding(.leading, 22)
    }

}

struct IOSPrototypeSearchField: View {
    @Bindable var store: IOSPrototypeStore

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索项目、任务或备忘录", text: $store.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: IOSPrototypeBottomBarMetrics.controlSize)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            isFocused = true
        }
    }
}

struct IOSPrototypeSearchView: View {
    @Bindable var store: IOSPrototypeStore

    var body: some View {
        if !store.searchResults.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { index, result in
                        NavigationLink(value: result.projectID) {
                            HStack(spacing: 9) {
                                if let project = project(for: result) {
                                    Image(systemName: project.symbol)
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color(prototypeHex: project.accentHex))
                                        .frame(width: 20)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(result.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            store.navigate(to: result)
                        })
                        .buttonStyle(.plain)

                        if index < store.searchResults.count - 1 {
                            Divider()
                                .padding(.leading, 39)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.gray.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        }
    }

    private func project(for result: IOSPrototypeSearchResult) -> IOSPrototypeProject? {
        store.projects.first { $0.id == result.projectID }
    }
}

struct IOSPlaceholderView: View {
    let symbol: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Text("静态原型入口已预留")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
