import SwiftData
import SwiftUI

struct IOSPersistentOverviewView: View {
    @Environment(ServiceContainer.self) private var services
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @Bindable var coordinator: IOSPersistenceCoordinator
    let projects: [Project]
    let archiveFolders: [ArchiveFolder]

    @State private var editingProject: Project?
    @State private var archivePickerProject: Project?
    @State private var projectPendingDeletionID: UUID?
    @State private var projectAwaitingFinalDeletionID: UUID?
    @State private var isSettingsPresented = false
    @State private var isProjectCreationPresented = false
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
                switch coordinator.homeTab {
                case .overview:
                    overview
                case .reports:
                    IOSPlaceholderView(symbol: "checkmark.seal.fill", title: "报告")
                case .archive:
                    IOSPersistentArchiveView(
                        coordinator: coordinator,
                        projects: projects,
                        archiveFolders: archiveFolders,
                        rootFolderCreationTrigger: archiveRootFolderCreationTrigger,
                        isComposerPresented: $isArchiveComposerPresented
                    )
                }
            }

            footer
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
                .zIndex(10)
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $isSettingsPresented) {
            IOSPersistentSettingsView()
        }
        .sheet(isPresented: $isProjectCreationPresented) {
            IOSPersistentProjectCreationView()
        }
        .sheet(item: $editingProject) { project in
            IOSPersistentProjectCreationView(editingProject: project)
        }
        .sheet(item: $archivePickerProject) { project in
            IOSPersistentArchiveFolderPicker(
                folders: archiveFolders,
                currentFolderID: nil,
                actionTitle: "归档"
            ) { folder in
                services.projectService?.archiveProject(project, to: folder)
            }
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

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if !isArchiveComposerPresented {
                if coordinator.isSearchPresented {
                    IOSPersistentSearchView(
                        coordinator: coordinator,
                        projects: projects,
                        effectiveLanguage: effectiveLanguage
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    HStack(spacing: 10) {
                        IOSPersistentSearchField(coordinator: coordinator)
                        IOSPrototypeDetachedActionButton(symbol: "xmark") {
                            withAnimation(.snappy(duration: 0.22)) {
                                coordinator.isSearchPresented = false
                                coordinator.searchText = ""
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        IOSPrototypeHomeTabBar(selection: $coordinator.homeTab)
                            .frame(maxWidth: .infinity)
                        if coordinator.homeTab == .archive {
                            IOSPrototypeDetachedActionButton(symbol: "folder.badge.plus") {
                                archiveRootFolderCreationTrigger = UUID()
                            }
                        } else {
                            IOSPrototypeDetachedActionButton(symbol: "magnifyingglass") {
                                withAnimation(.snappy(duration: 0.22)) {
                                    coordinator.isSearchPresented = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var overview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    IOSPrototypeCircularIconButton(symbol: "gearshape.fill") {
                        isSettingsPresented = true
                    }
                    Spacer()
                    IOSPrototypeCircularIconButton(symbol: "plus.app") {
                        isProjectCreationPresented = true
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 4)

                if !favoriteProjects.isEmpty {
                    IOSPrototypeSectionLabel(title: "星标项目")
                    ForEach(favoriteProjects, id: \.projectId) { project in
                        projectCardLink(project)
                    }
                }

                if !regularProjects.isEmpty {
                    IOSPrototypeSectionLabel(title: "其他项目")
                        .padding(.top, 4)
                    ForEach(regularProjects, id: \.projectId) { project in
                        projectCardLink(project)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 112)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func projectCardLink(_ project: Project) -> some View {
        Button {
            coordinator.selectProject(project)
        } label: {
            IOSPersistentOverviewProjectCard(
                project: project,
                onEdit: { editingProject = project },
                onArchive: { archivePickerProject = project },
                onToggleFavorite: { services.projectService?.toggleFavorite(project) },
                onDelete: { projectPendingDeletionID = project.projectId }
            )
        }
        .buttonStyle(.plain)
    }

    private var activeProjects: [Project] {
        OverviewScope.visibleProjects(
            from: projects,
            storedValue: settingsRecords.first?.overviewScope
        )
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private var favoriteProjects: [Project] {
        activeProjects.filter(\.isFavorite)
    }

    private var regularProjects: [Project] {
        activeProjects.filter { !$0.isFavorite }
    }

    private var pendingDeletionProject: Project? {
        guard let projectPendingDeletionID else { return nil }
        return projects.first { $0.projectId == projectPendingDeletionID }
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

struct IOSPersistentOverviewProjectCard: View {
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    let project: Project
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: project.sfSymbolName)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                    Text(project.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(Color.primary) : AnyShapeStyle(ViabarColor.primary))
                    Spacer()
                    if project.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ViabarColor.warning)
                    }
                }

                Spacer().frame(height: 18)

                if let milestone = topMilestone {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .frame(width: 16)
                        Text(milestone.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color(hex: "#4B5563")))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)

                    if let subtask = milestone.subtasks
                        .sorted(by: { $0.orderIndex < $1.orderIndex })
                        .first(where: { !$0.isCompleted }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.gray)
                                .frame(width: 16)
                            Text(subtask.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.gray)
                                .lineLimit(1)
                        }
                        .padding(.leading, 22)
                        .padding(.top, 10)
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    if let reminder = topMilestone?.reminder {
                        IOSPersistentReminderSummary(
                            reminder: reminder,
                            dateFormatPattern: savedDateFormat,
                            language: effectiveLanguage,
                            font: .system(size: 11)
                        )
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
            .padding(.vertical, 12)
        }
        .frame(height: 150)
        .iosPrototypeCardSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button("归档", systemImage: "archivebox", action: onArchive)
            Button(LocalizedStringKey(project.isFavorite ? "取消收藏" : "收藏"), systemImage: project.isFavorite ? "star.slash" : "star", action: onToggleFavorite)
            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var accentColor: Color {
        project.progress >= 1 ? ViabarColor.success : Color(hex: project.accentColor)
    }

    private var topMilestone: Milestone? {
        project.unfinishedMilestones.first
    }

    private var savedDateFormat: String? {
        settingsRecords.first?.dateFormat
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }
}

struct IOSPersistentSearchField: View {
    @Bindable var coordinator: IOSPersistenceCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索项目、任务或备忘录", text: $coordinator.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
            if !coordinator.searchText.isEmpty {
                Button {
                    coordinator.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: IOSPrototypeBottomBarMetrics.controlSize)
        .background(IOSPrototypeSurfaceStyle.inputBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
        .iosPrototypeInteractiveRoundedSurface(cornerRadius: 18)
        .onAppear {
            isFocused = true
        }
    }
}

struct IOSPersistentSearchView: View {
    @Bindable var coordinator: IOSPersistenceCoordinator
    let projects: [Project]
    let effectiveLanguage: EffectiveAppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var results: [GlobalSearchResult] {
        GlobalSearchIndex.results(
            matching: coordinator.searchText,
            projects: projects,
            archiveLabel: AppLocalization.string("归档", language: effectiveLanguage),
            memoLabel: AppLocalization.string("备忘录", language: effectiveLanguage)
        )
    }

    var body: some View {
        if !results.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            if result.project.isArchived {
                                coordinator.revealArchiveAncestors(for: result.project)
                            }
                            coordinator.navigate(to: result)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: result.project.sfSymbolName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color(hex: result.project.accentColor))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.text)
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
                            .contentShape(Rectangle())
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < results.count - 1 {
                            Divider()
                                .padding(.leading, 39)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            .iosPrototypeCardSurface(cornerRadius: 14)
            .shadow(color: IOSPrototypeSurfaceStyle.shadow(for: colorScheme), radius: 14, y: 5)
        }
    }
}
