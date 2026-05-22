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

    func removeEntry(ownerId: UUID) {
        entries(for: ownerId).forEach { modelContext.delete($0) }
        save()
        scheduleNextTimer()
    }

    func processDueEntries() {
        let now = Date()
        let dueEntries = allEntries()
            .filter { $0.fireDate <= now }
            .sorted { $0.fireDate < $1.fireDate }

        for entry in dueEntries {
            postNotification(title: entry.projectTitle, body: entry.body)
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

        guard !isCompleted, let fireDate = reminder?.timelineFireDate else {
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

    private func allEntries() -> [NotificationScheduleEntry] {
        let descriptor = FetchDescriptor<NotificationScheduleEntry>(
            sortBy: [SortDescriptor(\.fireDate)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func save() {
        guard modelContext.hasChanges else { return }
        try? modelContext.save()
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
