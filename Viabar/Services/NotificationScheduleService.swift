import Foundation
import SwiftData
import UserNotifications

@MainActor
final class NotificationScheduleService: NSObject, UNUserNotificationCenterDelegate {
    private let modelContext: ModelContext
    private var timer: Timer?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    func processDueEntries() {
        let now = Date()
        let dueEntries = allEntries()
            .filter { $0.fireDate <= now }
            .sorted { $0.fireDate < $1.fireDate }

        for entry in dueEntries {
            if entry.ownerKind == "project" {
                handleDueProjectEntry(entry, now: now)
                continue
            }

            if let notification = notificationContent(for: entry) {
                postNotification(title: notification.title, body: notification.body)
            }
            modelContext.delete(entry)
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
        entries(for: ownerId).forEach { modelContext.delete($0) }

        guard !project.isArchived, !isCompleted, let fireDate = reminder?.timelineFireDate else {
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
        modelContext.insert(entry)
        save()
        processDueEntries()
    }

    private func postNotification(title: String, body: String) {
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

        postNotification(title: project.title, body: nextStepBody(for: nextTaskTitle))

        guard let reminder = project.reminder else { return }
        guard reminder.type == "repeating" else {
            project.reminder = nil
            return
        }

        guard let nextDate = nextProjectRepeatFireDate(after: entry.fireDate, reminder: reminder, now: now) else {
            return
        }

        reminder.fireTimestamp = nextDate
        insertProjectEntry(for: project, fireDate: nextDate)
    }

    private func notificationContent(for entry: NotificationScheduleEntry) -> (title: String, body: String)? {
        guard entry.ownerKind == "project" else {
            guard let project = project(id: entry.projectId),
                  !project.isArchived
            else { return nil }
            return (project.title, entry.body)
        }

        guard let project = project(id: entry.projectId),
              !project.isArchived,
              let nextTaskTitle = project.topUnfinishedTitle
        else { return nil }

        return (project.title, nextStepBody(for: nextTaskTitle))
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

    private func nextProjectRepeatFireDate(after firedDate: Date, reminder: Reminder, now: Date) -> Date? {
        var candidate = firedDate
        for _ in 0..<10000 {
            guard let nextDate = nextRepeatFireDate(after: candidate, repeatIntervalDays: reminder.repeatIntervalDays) else {
                return nil
            }

            if nextDate > now {
                return nextDate
            }

            candidate = nextDate
        }
        return nil
    }

    private func nextRepeatFireDate(after date: Date, repeatIntervalDays: Int?) -> Date? {
        let calendar = Calendar.current
        switch repeatIntervalDays {
        case 0:
            return calendar.date(byAdding: .hour, value: 1, to: date)
        case -1:
            return nextWeekday(after: date)
        case 30:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case 90:
            return calendar.date(byAdding: .month, value: 3, to: date)
        case 180:
            return calendar.date(byAdding: .month, value: 6, to: date)
        case 365:
            return calendar.date(byAdding: .year, value: 1, to: date)
        default:
            return calendar.date(byAdding: .day, value: repeatIntervalDays ?? 1, to: date)
        }
    }

    private func nextWeekday(after date: Date) -> Date? {
        var candidate = Calendar.current.date(byAdding: .day, value: 1, to: date)
        while let current = candidate {
            let weekday = Calendar.current.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 {
                return current
            }
            candidate = Calendar.current.date(byAdding: .day, value: 1, to: current)
        }
        return nil
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
        let format = AppLocalization.string("下一步：%@", language: language)
        return String(format: format, title)
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
