import Foundation
import Observation
import SwiftData

enum BackupServiceError: LocalizedError {
    case unsupportedFormat
    case missingPayload
    case commandFailed(String)
    case invalidPath
    case authorizationRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "The selected backup format is not supported."
        case .missingPayload:
            return "The selected backup is missing backup.json."
        case .commandFailed(let output):
            return output.isEmpty ? "Backup archive operation failed." : output
        case .invalidPath:
            return "The selected backup path is invalid."
        case .authorizationRequired:
            return "Select a backup folder to grant write access before creating backups."
        }
    }
}

@MainActor
@Observable
final class BackupService {
    private let modelContext: ModelContext
    private let notificationScheduleService: NotificationScheduleService
    private let trashService: TrashService
    private let fileManager: FileManager
    private var timer: Timer?

    private(set) var availableBackups: [BackupFileMetadata] = []
    private(set) var latestBackup: BackupFileMetadata?
    private(set) var lastError: String?

    init(
        modelContext: ModelContext,
        notificationScheduleService: NotificationScheduleService,
        trashService: TrashService,
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.notificationScheduleService = notificationScheduleService
        self.trashService = trashService
        self.fileManager = fileManager
    }

    func start(settings: AppSettings) {
        setAutomaticBackupEnabled(settings.backupEnabled, settings: settings)
    }

    func authorizeBackupDirectory(_ directory: URL, settings: AppSettings) throws {
        let bookmarkData = try directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        settings.backupPath = directory.path
        settings.backupBookmarkData = bookmarkData
        try modelContext.save()
        try refreshBackups(settings: settings)
    }

    func refreshBackups(settings: AppSettings) throws {
        try withAuthorizedDirectory(settings: settings) { directory in
            try refreshBackups(in: directory)
        }
    }

    private func refreshBackups(in directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            availableBackups = []
            latestBackup = nil
            return
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        availableBackups = BackupFileMetadata.sortedNewestFirst(urls.compactMap(BackupFileMetadata.init))
        latestBackup = availableBackups.first
    }

    @discardableResult
    func createBackup(settings: AppSettings, now: Date = Date()) throws -> BackupFileMetadata {
        try withAuthorizedDirectory(settings: settings) { directory in
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let snapshot = try makeSnapshot(settings: settings, now: now)
            let archiveURL = uniqueArchiveURL(in: directory, date: now)
            let temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("viabar-backup-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: temporaryDirectory) }

            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let payloadURL = temporaryDirectory.appendingPathComponent("backup.json")
            let zipURL = temporaryDirectory.appendingPathComponent("archive.zip")
            try JSONEncoder.backupEncoder.encode(snapshot).write(to: payloadURL, options: .atomic)
            try runDitto(["-c", "-k", "--sequesterRsrc", payloadURL.path, zipURL.path])
            try fileManager.moveItem(at: zipURL, to: archiveURL)

            try refreshBackups(in: directory)
            try applyRetention(in: directory, now: now)
            let metadata = BackupFileMetadata(url: archiveURL) ?? BackupFileMetadata(url: archiveURL, createdAt: now)
            latestBackup = availableBackups.first
            lastError = nil
            return metadata
        }
    }

    func restore(file: BackupFileMetadata, settings: AppSettings) throws {
        try withAuthorizedDirectory(settings: settings) { _ in
            try restore(snapshot: decodeSnapshot(from: file.url))
        }
    }

    func restore(snapshot: BackupSnapshot, now: Date = Date()) throws {
        guard snapshot.formatVersion == BackupSnapshot.currentFormatVersion else {
            throw BackupServiceError.unsupportedFormat
        }

        deleteExistingRecoverableData()
        let settings = AppSettingsStore.ensureDefaultSettings(in: modelContext)
        apply(snapshot.settings, to: settings)
        let folders = restoreFolders(snapshot.folders)
        restoreTemplates(snapshot.templates)
        let projects = restoreProjects(snapshot.projects, folders: folders)
        try restoreTrashItems(snapshot.trashItems)
        try modelContext.save()
        try trashService.cleanupExpired(
            policy: TrashRetentionSettingsStore.policy(),
            now: now
        )
        notificationScheduleService.rebuildTimeline(from: projects)
        try? refreshBackups(settings: settings)
        setAutomaticBackupEnabled(settings.backupEnabled, settings: settings)
        lastError = nil
    }

    func setAutomaticBackupEnabled(_ enabled: Bool, settings: AppSettings) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }

        createAutomaticBackupIfNeeded(settings: settings)
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self, weak settings] _ in
            Task { @MainActor in
                guard let settings else { return }
                self?.createAutomaticBackupIfNeeded(settings: settings)
            }
        }
    }

    func latestBackupText(language: EffectiveAppLanguage, now: Date = Date()) -> String {
        guard let latestBackup else {
            return AppLocalization.string("暂无备份", language: language)
        }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = .current
        formatter.dateFormat = Calendar.current.isDateInToday(latestBackup.createdAt)
            ? "HH:mm"
            : "yyyy-MM-dd HH:mm"
        if Calendar.current.isDateInToday(latestBackup.createdAt) {
            return AppLocalization.format("今天 %@", language: language, formatter.string(from: latestBackup.createdAt))
        }
        return formatter.string(from: latestBackup.createdAt)
    }

    private func createAutomaticBackupIfNeeded(settings: AppSettings, now: Date = Date()) {
        do {
            try refreshBackups(settings: settings)
            if let latestBackup, Calendar.current.isDate(latestBackup.createdAt, equalTo: now, toGranularity: .hour) {
                return
            }
            try createBackup(settings: settings, now: now)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyRetention(in directory: URL, now: Date) throws {
        let deletes = BackupRetentionPolicy.urlsToDelete(from: availableBackups, now: now)
        for url in deletes {
            try fileManager.removeItem(at: url)
        }
        try refreshBackups(in: directory)
    }

    private func makeSnapshot(settings: AppSettings, now: Date) throws -> BackupSnapshot {
        let folders = try modelContext.fetch(FetchDescriptor<ArchiveFolder>())
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let templates = try modelContext.fetch(FetchDescriptor<ProjectTemplate>())
        let trashItems = trashService.allItems()

        return BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            createdAt: now,
            settings: BackupSettingsSnapshot(settings: settings),
            folders: folders.map {
                BackupFolderSnapshot(
                    folderId: $0.folderId,
                    name: $0.name,
                    orderIndex: $0.orderIndex,
                    parentId: $0.parent?.folderId
                )
            },
            projects: projects.map(projectSnapshot),
            templates: templates.map(templateSnapshot),
            trashItems: trashItems.map(trashSnapshot)
        )
    }

    private func projectSnapshot(_ project: Project) -> BackupProjectSnapshot {
        BackupProjectSnapshot(
            projectId: project.projectId,
            title: project.title,
            hideCompleted: project.hideCompleted,
            isArchived: project.isArchived,
            isFavorite: project.isFavorite,
            orderIndex: project.orderIndex,
            archivedAt: project.archivedAt,
            accentColor: project.accentColor,
            sfSymbolName: project.sfSymbolName,
            archiveFolderId: project.archiveFolder?.folderId,
            reminder: project.reminder.map(BackupReminderSnapshot.init),
            milestones: project.milestones.map {
                BackupMilestoneSnapshot(
                    milestoneId: $0.milestoneId,
                    title: $0.title,
                    isCompleted: $0.isCompleted,
                    completedAt: $0.completedAt,
                    orderIndex: $0.orderIndex,
                    reminder: $0.reminder.map(BackupReminderSnapshot.init),
                    subtasks: $0.subtasks.map {
                        BackupSubTaskSnapshot(
                            taskId: $0.taskId,
                            title: $0.title,
                            isCompleted: $0.isCompleted,
                            completedAt: $0.completedAt,
                            orderIndex: $0.orderIndex,
                            reminder: $0.reminder.map(BackupReminderSnapshot.init)
                        )
                    }
                )
            },
            memos: project.memos.map {
                BackupMemoSnapshot(
                    memoId: $0.memoId,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    orderIndex: $0.orderIndex
                )
            }
        )
    }

    private func templateSnapshot(_ template: ProjectTemplate) -> BackupTemplateSnapshot {
        BackupTemplateSnapshot(
            templateId: template.templateId,
            name: template.name,
            hideCompleted: template.hideCompleted,
            orderIndex: template.orderIndex,
            accentColor: template.accentColor,
            sfSymbolName: template.sfSymbolName,
            milestones: template.milestones.map {
                BackupTemplateMilestoneSnapshot(
                    milestoneId: $0.milestoneId,
                    title: $0.title,
                    orderIndex: $0.orderIndex,
                    subtasks: $0.subtasks.map {
                        BackupTemplateSubTaskSnapshot(
                            taskId: $0.taskId,
                            title: $0.title,
                            orderIndex: $0.orderIndex
                        )
                    }
                )
            }
        )
    }

    private func decodeSnapshot(from archiveURL: URL) throws -> BackupSnapshot {
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("viabar-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let localArchiveURL = temporaryDirectory.appendingPathComponent(archiveURL.lastPathComponent)
        try fileManager.copyItem(at: archiveURL, to: localArchiveURL)
        try runDitto(["-x", "-k", localArchiveURL.path, temporaryDirectory.path])
        let payloadURL = temporaryDirectory.appendingPathComponent("backup.json")
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw BackupServiceError.missingPayload
        }
        let snapshot = try JSONDecoder.backupDecoder.decode(BackupSnapshot.self, from: Data(contentsOf: payloadURL))
        guard snapshot.formatVersion == BackupSnapshot.currentFormatVersion else {
            throw BackupServiceError.unsupportedFormat
        }
        return snapshot
    }

    private func deleteExistingRecoverableData() {
        for entry in (try? modelContext.fetch(FetchDescriptor<NotificationScheduleEntry>())) ?? [] {
            modelContext.delete(entry)
        }
        for project in (try? modelContext.fetch(FetchDescriptor<Project>())) ?? [] {
            modelContext.delete(project)
        }
        for template in (try? modelContext.fetch(FetchDescriptor<ProjectTemplate>())) ?? [] {
            modelContext.delete(template)
        }
        for folder in (try? modelContext.fetch(FetchDescriptor<ArchiveFolder>())) ?? [] {
            modelContext.delete(folder)
        }
    }

    private func restoreFolders(_ snapshots: [BackupFolderSnapshot]) -> [UUID: ArchiveFolder] {
        var folders: [UUID: ArchiveFolder] = [:]
        for snapshot in snapshots {
            let folder = ArchiveFolder(name: snapshot.name, orderIndex: snapshot.orderIndex)
            folder.folderId = snapshot.folderId
            modelContext.insert(folder)
            folders[snapshot.folderId] = folder
        }
        for snapshot in snapshots {
            folders[snapshot.folderId]?.parent = snapshot.parentId.flatMap { folders[$0] }
        }
        return folders
    }

    private func restoreTemplates(_ snapshots: [BackupTemplateSnapshot]) {
        for snapshot in snapshots {
            let template = ProjectTemplate(
                name: snapshot.name,
                hideCompleted: snapshot.hideCompleted,
                orderIndex: snapshot.orderIndex,
                accentColor: snapshot.accentColor,
                sfSymbolName: snapshot.sfSymbolName
            )
            template.templateId = snapshot.templateId
            modelContext.insert(template)
            for milestoneSnapshot in snapshot.milestones {
                let milestone = TemplateMilestone(title: milestoneSnapshot.title, orderIndex: milestoneSnapshot.orderIndex)
                milestone.milestoneId = milestoneSnapshot.milestoneId
                milestone.template = template
                modelContext.insert(milestone)
                template.milestones.append(milestone)
                for subtaskSnapshot in milestoneSnapshot.subtasks {
                    let subtask = TemplateSubTask(title: subtaskSnapshot.title, orderIndex: subtaskSnapshot.orderIndex)
                    subtask.taskId = subtaskSnapshot.taskId
                    subtask.milestone = milestone
                    modelContext.insert(subtask)
                    milestone.subtasks.append(subtask)
                }
            }
        }
    }

    private func restoreProjects(
        _ snapshots: [BackupProjectSnapshot],
        folders: [UUID: ArchiveFolder]
    ) -> [Project] {
        snapshots.map { snapshot in
            let project = Project(
                title: snapshot.title,
                hideCompleted: snapshot.hideCompleted,
                orderIndex: snapshot.orderIndex
            )
            project.projectId = snapshot.projectId
            project.isArchived = snapshot.isArchived
            project.isFavorite = snapshot.isFavorite
            project.archivedAt = snapshot.archivedAt
            project.accentColor = snapshot.accentColor
            project.sfSymbolName = snapshot.sfSymbolName
            project.archiveFolder = snapshot.archiveFolderId.flatMap { folders[$0] }
            project.reminder = snapshot.reminder.map(restoreReminder)
            modelContext.insert(project)
            for milestoneSnapshot in snapshot.milestones {
                let milestone = Milestone(
                    title: milestoneSnapshot.title,
                    orderIndex: milestoneSnapshot.orderIndex,
                    isCompleted: milestoneSnapshot.isCompleted
                )
                milestone.milestoneId = milestoneSnapshot.milestoneId
                milestone.completedAt = milestoneSnapshot.completedAt
                milestone.reminder = milestoneSnapshot.reminder.map(restoreReminder)
                milestone.project = project
                modelContext.insert(milestone)
                project.milestones.append(milestone)
                for subtaskSnapshot in milestoneSnapshot.subtasks {
                    let subtask = SubTask(
                        title: subtaskSnapshot.title,
                        orderIndex: subtaskSnapshot.orderIndex,
                        isCompleted: subtaskSnapshot.isCompleted
                    )
                    subtask.taskId = subtaskSnapshot.taskId
                    subtask.completedAt = subtaskSnapshot.completedAt
                    subtask.reminder = subtaskSnapshot.reminder.map(restoreReminder)
                    subtask.milestone = milestone
                    modelContext.insert(subtask)
                    milestone.subtasks.append(subtask)
                }
            }
            for memoSnapshot in snapshot.memos {
                let memo = Memo(
                    content: memoSnapshot.content,
                    createdAt: memoSnapshot.createdAt,
                    orderIndex: memoSnapshot.orderIndex
                )
                memo.memoId = memoSnapshot.memoId
                memo.project = project
                modelContext.insert(memo)
                project.memos.append(memo)
            }
            return project
        }
    }

    private func restoreReminder(_ snapshot: BackupReminderSnapshot) -> Reminder {
        let reminder = Reminder(
            type: snapshot.type,
            fireTime: snapshot.fireTime,
            fireTimestamp: snapshot.fireTimestamp,
            repeatIntervalDays: snapshot.repeatIntervalDays
        )
        reminder.reminderId = snapshot.reminderId
        reminder.lastTriggeredTimestamp = snapshot.lastTriggeredTimestamp
        modelContext.insert(reminder)
        return reminder
    }

    private func trashSnapshot(_ item: TrashItem) -> BackupTrashItemSnapshot {
        BackupTrashItemSnapshot(
            trashItemId: item.trashItemId,
            kind: item.kind,
            deletedAt: item.deletedAt,
            originalProjectId: item.originalProjectId,
            originalProjectTitle: item.originalProjectTitle,
            originalProjectAccentColor: item.originalProjectAccentColor,
            originalProjectSymbolName: item.originalProjectSymbolName,
            originalParentTaskId: item.originalParentTaskId,
            originalParentTaskTitle: item.originalParentTaskTitle,
            originalOrderIndex: item.originalOrderIndex,
            payloadVersion: item.payloadVersion,
            payloadData: item.payloadData
        )
    }

    private func restoreTrashItems(_ snapshots: [BackupTrashItemSnapshot]) throws {
        try trashService.replaceItems(
            with: snapshots.map { snapshot in
                TrashItem(
                    trashItemId: snapshot.trashItemId,
                    kind: TrashItemKind(rawValue: snapshot.kind) ?? .memo,
                    deletedAt: snapshot.deletedAt,
                    originalProjectId: snapshot.originalProjectId,
                    originalProjectTitle: snapshot.originalProjectTitle,
                    originalProjectAccentColor: snapshot.originalProjectAccentColor,
                    originalProjectSymbolName: snapshot.originalProjectSymbolName,
                    originalParentTaskId: snapshot.originalParentTaskId,
                    originalParentTaskTitle: snapshot.originalParentTaskTitle,
                    originalOrderIndex: snapshot.originalOrderIndex,
                    payloadVersion: snapshot.payloadVersion,
                    payloadData: snapshot.payloadData
                )
            }
        )
    }

    private func apply(_ snapshot: BackupSettingsSnapshot, to settings: AppSettings) {
        settings.settingsId = snapshot.settingsId
        settings.createdAt = snapshot.createdAt
        settings.launchAtLogin = snapshot.launchAtLogin
        settings.menuBarComponentEnabled = snapshot.menuBarComponentEnabled
        settings.menuBarIcon = snapshot.menuBarIcon
        settings.menuBarProjectScope = snapshot.menuBarProjectScope
        settings.menuBarContentMode = snapshot.menuBarContentMode
        settings.theme = snapshot.theme
        settings.language = snapshot.language
        settings.overviewScope = snapshot.overviewScope
        WeekStartDaySettingsStore.set(WeekStartDay.resolve(snapshot.weekStartDay))
        settings.weekdayFilterEnabled = snapshot.weekdayFilterEnabled
        settings.dateFormat = snapshot.dateFormat
        settings.toggleMainPanelShortcut = snapshot.toggleMainPanelShortcut
        settings.openSearchShortcut = snapshot.openSearchShortcut
        settings.syncEnabled = snapshot.syncEnabled
        settings.lastSyncAt = snapshot.lastSyncAt
        settings.backupEnabled = snapshot.backupEnabled
        TrashRetentionSettingsStore.set(TrashRetentionPolicy.resolve(snapshot.trashRetentionPolicy))
        // The authorized backup destination is local to this Mac and is not restored from an archive.
        settings.automaticallyChecksForUpdates = snapshot.automaticallyChecksForUpdates
    }

    private func withAuthorizedDirectory<Result>(
        settings: AppSettings,
        operation: (URL) throws -> Result
    ) throws -> Result {
        guard let bookmarkData = settings.backupBookmarkData else {
            throw BackupServiceError.authorizationRequired
        }

        var isStale = false
        let directory = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard directory.startAccessingSecurityScopedResource() else {
            throw BackupServiceError.authorizationRequired
        }
        defer { directory.stopAccessingSecurityScopedResource() }

        if isStale {
            settings.backupBookmarkData = try directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            settings.backupPath = directory.path
            try modelContext.save()
        }

        return try operation(directory)
    }

    private func uniqueArchiveURL(in directory: URL, date: Date) -> URL {
        var candidateDate = date
        var candidate = BackupFileMetadata.url(in: directory, date: candidateDate)
        while fileManager.fileExists(atPath: candidate.path) {
            candidateDate = candidateDate.addingTimeInterval(1)
            candidate = BackupFileMetadata.url(in: directory, date: candidateDate)
        }
        return candidate
    }

    private func runDitto(_ arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw BackupServiceError.commandFailed(output)
        }
    }
}

extension ServiceContainer {
    var backupService: BackupService? {
        resolve(BackupService.self)
    }

    func registerBackupService(
        modelContext: ModelContext,
        notificationScheduleService: NotificationScheduleService,
        trashService: TrashService
    ) -> BackupService {
        let service = BackupService(
            modelContext: modelContext,
            notificationScheduleService: notificationScheduleService,
            trashService: trashService
        )
        register(service)
        return service
    }
}
