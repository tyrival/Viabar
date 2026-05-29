import Foundation
import SwiftData
import UserNotifications

@MainActor
final class NotificationScheduleService: NSObject, UNUserNotificationCenterDelegate {
    private let modelContext: ModelContext
    private let notificationPoster: (String, String) -> Void
    private var timer: Timer?

    init(modelContext: ModelContext, notificationPoster: ((String, String) -> Void)? = nil) {
        self.modelContext = modelContext
        self.notificationPoster = notificationPoster ?? Self.deliverNotification
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.processDueEntries()
            }
        }
    }

    func syncMilestone(_ milestone: Milestone, project: Project) {
        syncEntry(
            ownerId: milestone.milestoneId,
            ownerKind: "milestone",
            project: project,
            body: milestone.title,
            reminder: milestone.reminder,
            isCompleted: milestone.isCompleted
        )
    }

    func syncSubTask(_ subTask: SubTask, project: Project) {
        syncEntry(
            ownerId: subTask.taskId,
            ownerKind: "subtask",
            project: project,
            body: subTask.title,
            reminder: subTask.reminder,
            isCompleted: subTask.isCompleted
        )
    }

    func syncProject(_ project: Project) {
        let nextTaskTitle = project.topUnfinishedTitle
        syncEntry(
            ownerId: project.projectId,
            ownerKind: "project",
            project: project,
            body: nextTaskTitle.map(nextStepBody(for:)) ?? "",
            reminder: project.reminder,
            isCompleted: project.isArchived || nextTaskTitle == nil
        )
    }

    func removeEntry(ownerId: UUID) {
        entries(for: ownerId).forEach { modelContext.delete($0) }
        save()
        scheduleNextTimer()
    }

    func removeEntries(projectId: UUID) {
        entries(forProjectId: projectId).forEach { modelContext.delete($0) }
        save()
        scheduleNextTimer()
    }

    func rebuildTimeline(from projects: [Project]) {
        allEntries().forEach { modelContext.delete($0) }
        save()

        for project in projects where !project.isArchived {
            syncProject(project)
            for milestone in project.milestones {
                syncMilestone(milestone, project: project)
                for subTask in milestone.subtasks {
                    syncSubTask(subTask, project: project)
                }
            }
        }
    }

    func processDueEntries(now: Date = Date()) {
        let dueEntries = allEntries()
            .filter { $0.fireDate <= now }
            .sorted { $0.fireDate < $1.fireDate }

        for entry in dueEntries {
            if entry.ownerKind == "project" {
                handleDueProjectEntry(entry, now: now)
                continue
            }

            handleDueTaskEntry(entry, now: now)
        }

        save()
        scheduleNextTimer()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    private func syncEntry(
        ownerId: UUID,
        ownerKind: String,
        project: Project,
        body: String,
        reminder: Reminder?,
        isCompleted: Bool
    ) {
        let oldCount = entries(for: ownerId).count
        entries(for: ownerId).forEach { modelContext.delete($0) }

        guard !project.isArchived, !isCompleted, let fireDate = reminder?.timelineFireDate else {
            print("[SyncEntry] \(ownerKind):\(ownerId) 清除\(oldCount)条旧条目，无需新建 (archived=\(project.isArchived) completed=\(isCompleted) hasReminder=\(reminder != nil))")
            save()
            scheduleNextTimer()
            return
        }

        let entry = NotificationScheduleEntry(
            ownerId: ownerId,
            ownerKind: ownerKind,
            projectId: project.projectId,
            projectTitle: project.title,
            body: body,
            fireDate: fireDate
        )
        print("[SyncEntry] \(ownerKind):\(ownerId) 清除\(oldCount)条旧条目，新建1条 fireDate=\(fireDate) body=\(body)")
        modelContext.insert(entry)
        save()
        processDueEntries()
    }

    private static func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func handleDueProjectEntry(_ entry: NotificationScheduleEntry, now: Date) {
        defer {
            modelContext.delete(entry)
        }

        guard let project = project(id: entry.projectId),
              !project.isArchived,
              let nextTaskTitle = project.topUnfinishedTitle
        else { return }

        notificationPoster(project.title, nextStepBody(for: nextTaskTitle))

        guard let reminder = project.reminder else { return }
        reminder.lastTriggeredTimestamp = entry.fireDate
        guard reminder.type == "repeating" else {
            project.reminder = nil
            return
        }

        guard let nextDate = reminder.nextFutureFireDate(after: entry.fireDate, now: now) else {
            return
        }

        reminder.fireTimestamp = nextDate
        insertProjectEntry(for: project, fireDate: nextDate)
    }

    private func handleDueTaskEntry(_ entry: NotificationScheduleEntry, now: Date) {
        defer {
            modelContext.delete(entry)
        }

        guard let project = project(id: entry.projectId), !project.isArchived,
              let owner = taskOwner(for: entry),
              !owner.isCompleted,
              let reminder = owner.reminder
        else { return }

        notificationPoster(project.title, owner.title)
        reminder.lastTriggeredTimestamp = entry.fireDate

        guard reminder.isRepeating,
              let nextDate = reminder.nextFutureFireDate(after: entry.fireDate, now: now)
        else { return }

        reminder.fireTimestamp = nextDate
        modelContext.insert(
            NotificationScheduleEntry(
                ownerId: entry.ownerId,
                ownerKind: entry.ownerKind,
                projectId: project.projectId,
                projectTitle: project.title,
                body: owner.title,
                fireDate: nextDate
            )
        )
    }

    private func insertProjectEntry(for project: Project, fireDate: Date) {
        guard let nextTaskTitle = project.topUnfinishedTitle else { return }
        let entry = NotificationScheduleEntry(
            ownerId: project.projectId,
            ownerKind: "project",
            projectId: project.projectId,
            projectTitle: project.title,
            body: nextStepBody(for: nextTaskTitle),
            fireDate: fireDate
        )
        modelContext.insert(entry)
    }

    private func scheduleNextTimer() {
        timer?.invalidate()
        timer = nil

        guard let nextEntry = allEntries()
            .filter({ $0.fireDate > Date() })
            .min(by: { $0.fireDate < $1.fireDate })
        else { return }

        let interval = max(0.2, nextEntry.fireDate.timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processDueEntries()
            }
        }
    }

    private func entries(for ownerId: UUID) -> [NotificationScheduleEntry] {
        let descriptor = FetchDescriptor<NotificationScheduleEntry>(
            predicate: #Predicate { $0.ownerId == ownerId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func entries(forProjectId projectId: UUID) -> [NotificationScheduleEntry] {
        let descriptor = FetchDescriptor<NotificationScheduleEntry>(
            predicate: #Predicate { $0.projectId == projectId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func allEntries() -> [NotificationScheduleEntry] {
        let descriptor = FetchDescriptor<NotificationScheduleEntry>(
            sortBy: [SortDescriptor(\.fireDate)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func project(id projectId: UUID) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.projectId == projectId }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func taskOwner(for entry: NotificationScheduleEntry) -> (
        title: String,
        isCompleted: Bool,
        reminder: Reminder?
    )? {
        if entry.ownerKind == "milestone" {
            let ownerID = entry.ownerId
            let descriptor = FetchDescriptor<Milestone>(
                predicate: #Predicate { $0.milestoneId == ownerID }
            )
            guard let milestone = (try? modelContext.fetch(descriptor))?.first else { return nil }
            return (milestone.title, milestone.isCompleted, milestone.reminder)
        }

        if entry.ownerKind == "subtask" {
            let ownerID = entry.ownerId
            let descriptor = FetchDescriptor<SubTask>(
                predicate: #Predicate { $0.taskId == ownerID }
            )
            guard let subTask = (try? modelContext.fetch(descriptor))?.first else { return nil }
            return (subTask.title, subTask.isCompleted, subTask.reminder)
        }

        return nil
    }

    private func save() {
        guard modelContext.hasChanges else { return }
        try? modelContext.save()
    }

    private func nextStepBody(for title: String) -> String {
        var descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\AppSettings.createdAt)]
        )
        descriptor.fetchLimit = 1
        let settings = (try? modelContext.fetch(descriptor))?.first
        let language = AppLanguage.effectiveLanguage(storedValue: settings?.language)
        return AppLocalization.format("下一步：%@", language: language, title)
    }
}

extension ServiceContainer {
    var notificationScheduleService: NotificationScheduleService? {
        resolve(NotificationScheduleService.self)
    }

    func registerNotificationScheduleService(modelContext: ModelContext) -> NotificationScheduleService {
        let service = NotificationScheduleService(modelContext: modelContext)
        register(service)
        return service
    }
}

private extension Reminder {
    var timelineFireDate: Date? {
        fireTimestamp
    }
}
