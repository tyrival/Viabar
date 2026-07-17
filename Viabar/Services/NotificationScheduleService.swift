import Foundation
import SwiftData
import UserNotifications
#if os(macOS)
import AppKit
#endif

enum NotificationOwnerKind: String, Sendable {
    case project
    case milestone
    case subtask
}

@MainActor
final class NotificationScheduleService: NSObject, UNUserNotificationCenterDelegate {
    private static let categoryIdentifier = "TASK_REMINDER"
    private static let requestPrefix = "viabar."

    private let modelContext: ModelContext
    private let notificationCenter: any UserNotificationCenterClient
#if os(macOS)
    private var wakeObserver: NSObjectProtocol?
#endif
    private var completeOwner: ((UUID, NotificationOwnerKind) -> Void)?
    private var hasStarted = false
    private var isReconciling = false

    init(
        modelContext: ModelContext,
        notificationCenter: any UserNotificationCenterClient
    ) {
        self.modelContext = modelContext
        self.notificationCenter = notificationCenter
        super.init()
    }

    convenience init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            notificationCenter: SystemUserNotificationCenterClient()
        )
    }

    deinit {
#if os(macOS)
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
#endif
    }

    func configureCompleteAction(_ handler: @escaping (UUID, NotificationOwnerKind) -> Void) {
        completeOwner = handler
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
        observeSystemWake()

        Task { @MainActor in
            do {
                switch await notificationCenter.currentAuthorizationStatus() {
                case .notDetermined:
                    guard try await notificationCenter.requestAuthorization() else { return }
                case .authorized, .provisional:
                    break
#if os(iOS)
                case .ephemeral:
                    break
#endif
                case .denied:
                    return
                @unknown default:
                    return
                }
                await reconcile()
            } catch {
                print("[NotificationSchedule] authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func applicationDidBecomeActive() {
        guard hasStarted else { return }
        Task { @MainActor in
            await reconcile()
        }
    }

    func recordNotificationHandled(
        ownerId: UUID,
        ownerKind: NotificationOwnerKind,
        fireDate: Date
    ) {
        guard let candidate = reminderCandidates().first(where: {
            $0.ownerId == ownerId && $0.ownerKind == ownerKind
        }) else { return }

        candidate.reminder.lastTriggeredTimestamp = max(
            candidate.reminder.lastTriggeredTimestamp ?? .distantPast,
            fireDate
        )
        save()
    }

    func syncMilestone(_ milestone: Milestone, project: Project) {
        syncEntry(
            ownerId: milestone.milestoneId,
            ownerKind: .milestone,
            project: project,
            body: milestone.title,
            reminder: milestone.reminder,
            isCompleted: milestone.isCompleted
        )
    }

    func syncSubTask(_ subTask: SubTask, project: Project) {
        syncEntry(
            ownerId: subTask.taskId,
            ownerKind: .subtask,
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
            ownerKind: .project,
            project: project,
            body: nextTaskTitle.map(nextStepBody(for:)) ?? "",
            reminder: project.reminder,
            isCompleted: project.isArchived || nextTaskTitle == nil
        )
    }

    func replaceMilestoneReminder(_ milestone: Milestone, project: Project) {
        removeDelivered(ownerId: milestone.milestoneId, ownerKind: .milestone)
        syncMilestone(milestone, project: project)
    }

    func replaceSubTaskReminder(_ subTask: SubTask, project: Project) {
        removeDelivered(ownerId: subTask.taskId, ownerKind: .subtask)
        syncSubTask(subTask, project: project)
    }

    func replaceProjectReminder(_ project: Project) {
        removeDelivered(ownerId: project.projectId, ownerKind: .project)
        syncProject(project)
    }

    func removeEntry(ownerId: UUID) {
        let ownerKinds = entries(for: ownerId).compactMap { NotificationOwnerKind(rawValue: $0.ownerKind) }
        entries(for: ownerId).forEach { modelContext.delete($0) }
        let identifiers = Set(ownerKinds.isEmpty ? NotificationOwnerKind.allCases.map {
            requestIdentifier(ownerKind: $0, ownerId: ownerId)
        } : ownerKinds.map {
            requestIdentifier(ownerKind: $0, ownerId: ownerId)
        })
        notificationCenter.removePendingRequests(withIdentifiers: Array(identifiers))
        save()
    }

    func removeEntries(projectId: UUID) {
        let projectEntries = entries(forProjectId: projectId)
        let identifiers = projectEntries.compactMap { entry -> String? in
            guard let kind = NotificationOwnerKind(rawValue: entry.ownerKind) else { return nil }
            return requestIdentifier(ownerKind: kind, ownerId: entry.ownerId)
        }
        projectEntries.forEach { modelContext.delete($0) }
        notificationCenter.removePendingRequests(withIdentifiers: identifiers)
        save()
    }

    func cancelMilestone(_ milestone: Milestone, removeDelivered: Bool = false) {
        cancel(ownerId: milestone.milestoneId, ownerKind: .milestone, removeDelivered: removeDelivered)
        milestone.subtasks.forEach {
            cancel(ownerId: $0.taskId, ownerKind: .subtask, removeDelivered: removeDelivered)
        }
    }

    func cancelSubTask(_ subTask: SubTask, removeDelivered: Bool = false) {
        cancel(ownerId: subTask.taskId, ownerKind: .subtask, removeDelivered: removeDelivered)
    }

    func cancelProject(_ project: Project, removeDelivered: Bool = false) {
        cancel(ownerId: project.projectId, ownerKind: .project, removeDelivered: removeDelivered)
        project.milestones.forEach { milestone in
            cancel(ownerId: milestone.milestoneId, ownerKind: .milestone, removeDelivered: removeDelivered)
            milestone.subtasks.forEach {
                cancel(ownerId: $0.taskId, ownerKind: .subtask, removeDelivered: removeDelivered)
            }
        }
    }

    func rebuildTimeline(from projects: [Project]) {
        allEntries().forEach { modelContext.delete($0) }
        save()

        for project in projects where !project.isArchived {
            syncProject(project)
            project.milestones.forEach { milestone in
                syncMilestone(milestone, project: project)
                milestone.subtasks.forEach { syncSubTask($0, project: project) }
            }
        }

        Task { @MainActor in
            await reconcile()
        }
    }

    func reconcile(now: Date = Date()) async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let authorization = await notificationCenter.currentAuthorizationStatus()
        switch authorization {
        case .authorized, .provisional:
            break
#if os(iOS)
        case .ephemeral:
            break
#endif
        default:
            return
        }

        let pendingRequests = await notificationCenter.pendingRequests()
        let pendingIDs = Set(pendingRequests.map(\.identifier))
        let deliveredIDs = await notificationCenter.deliveredRequestIdentifiers()
        let candidates = reminderCandidates()
        let validIDs = Set(candidates.map {
            requestIdentifier(ownerKind: $0.ownerKind, ownerId: $0.ownerId)
        })

        let staleIDs = pendingIDs.filter {
            $0.hasPrefix(Self.requestPrefix) && !validIDs.contains($0)
        }
        notificationCenter.removePendingRequests(withIdentifiers: Array(staleIDs))

        var overdueCandidates: [(candidate: ReminderCandidate, fireDate: Date)] = []
        var missedCandidates: [(candidate: ReminderCandidate, missedDate: Date)] = []

        for candidate in candidates {
            guard let fireDate = candidate.reminder.fireTimestamp else { continue }
            let identifier = requestIdentifier(ownerKind: candidate.ownerKind, ownerId: candidate.ownerId)

            if fireDate > now {
                if !pendingIDs.contains(identifier) {
                    await addFutureRequest(for: candidate, fireDate: fireDate)
                }
                continue
            }

            overdueCandidates.append((candidate, fireDate))
            if deliveredIDs.contains(identifier) {
                candidate.reminder.lastTriggeredTimestamp = max(
                    candidate.reminder.lastTriggeredTimestamp ?? .distantPast,
                    fireDate
                )
            } else if candidate.reminder.isRepeating {
                if let latestMissed = candidate.reminder.latestMissedFireDate(now: now),
                   latestMissed > (candidate.reminder.lastTriggeredTimestamp ?? .distantPast) {
                    missedCandidates.append((candidate, latestMissed))
                }
            } else if candidate.reminder.lastTriggeredTimestamp == nil {
                missedCandidates.append((candidate, fireDate))
            }
        }

        if let latestMissed = missedCandidates.max(by: { $0.missedDate < $1.missedDate }),
           await deliverMissedNotification(
               for: latestMissed.candidate,
               missedDate: latestMissed.missedDate
           ) {
            for missed in missedCandidates {
                missed.candidate.reminder.lastTriggeredTimestamp = missed.missedDate
            }
        }

        for overdue in overdueCandidates {
            let candidate = overdue.candidate
            let fireDate = overdue.fireDate
            guard candidate.reminder.isRepeating,
                  let nextDate = candidate.reminder.nextFutureFireDate(after: fireDate, now: now)
            else { continue }

            candidate.reminder.fireTimestamp = nextDate
            replaceScheduleEntry(for: candidate, fireDate: nextDate)
            await addFutureRequest(for: candidate, fireDate: nextDate)
        }

        save()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard let metadata = Self.notificationMetadata(
            from: notification.request.content.userInfo
        ) else {
            completionHandler([.banner, .sound, .list])
            return
        }

        Task { @MainActor in
            self.recordNotificationHandled(
                ownerId: metadata.ownerId,
                ownerKind: metadata.ownerKind,
                fireDate: metadata.fireDate
            )
            Task { @MainActor in
                await self.reconcile()
            }
            completionHandler([.banner, .sound, .list])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let handledActions = [
            "IGNORE",
            "COMPLETE_TASK",
            UNNotificationDefaultActionIdentifier,
            UNNotificationDismissActionIdentifier,
        ]
        guard handledActions.contains(actionIdentifier),
              let metadata = Self.notificationMetadata(
                  from: response.notification.request.content.userInfo
              )
        else {
            completionHandler()
            return
        }

        Task { @MainActor in
            self.recordNotificationHandled(
                ownerId: metadata.ownerId,
                ownerKind: metadata.ownerKind,
                fireDate: metadata.fireDate
            )
            if actionIdentifier == "COMPLETE_TASK", metadata.ownerKind != .project {
                self.completeOwner?(metadata.ownerId, metadata.ownerKind)
            } else {
                Task { @MainActor in
                    await self.reconcile()
                }
            }
            completionHandler()
        }
    }

    nonisolated private static func notificationMetadata(
        from userInfo: [AnyHashable: Any]
    ) -> (ownerId: UUID, ownerKind: NotificationOwnerKind, fireDate: Date)? {
        guard let ownerIdString = userInfo["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let ownerKindString = userInfo["ownerKind"] as? String,
              let ownerKind = NotificationOwnerKind(rawValue: ownerKindString),
              let timestamp = userInfo["fireTimestamp"] as? TimeInterval
        else { return nil }

        return (ownerId, ownerKind, Date(timeIntervalSince1970: timestamp))
    }

    private func syncEntry(
        ownerId: UUID,
        ownerKind: NotificationOwnerKind,
        project: Project,
        body: String,
        reminder: Reminder?,
        isCompleted: Bool
    ) {
        entries(for: ownerId).forEach { modelContext.delete($0) }
        let identifier = requestIdentifier(ownerKind: ownerKind, ownerId: ownerId)
        notificationCenter.removePendingRequests(withIdentifiers: [identifier])

        guard !project.isArchived,
              !isCompleted,
              let reminder,
              let fireDate = reminder.fireTimestamp
        else {
            save()
            return
        }

        let entry = NotificationScheduleEntry(
            ownerId: ownerId,
            ownerKind: ownerKind.rawValue,
            projectId: project.projectId,
            projectTitle: project.title,
            body: body,
            fireDate: fireDate
        )
        modelContext.insert(entry)
        save()

        guard fireDate > Date(),
              reminder.isRepeating || reminder.lastTriggeredTimestamp == nil
        else { return }

        let candidate = ReminderCandidate(
            ownerId: ownerId,
            ownerKind: ownerKind,
            project: project,
            body: body,
            reminder: reminder
        )
        Task { @MainActor in
            await addFutureRequest(for: candidate, fireDate: fireDate)
        }
    }

    private func addFutureRequest(for candidate: ReminderCandidate, fireDate: Date) async {
        let identifier = requestIdentifier(ownerKind: candidate.ownerKind, ownerId: candidate.ownerId)
        let request = makeRequest(
            identifier: identifier,
            candidate: candidate,
            fireDate: fireDate,
            trigger: calendarTrigger(for: fireDate)
        )
        do {
            try await notificationCenter.add(request)
            if !isCandidateActive(candidate, fireDate: fireDate) {
                notificationCenter.removePendingRequests(withIdentifiers: [identifier])
            }
        } catch {
            print("[NotificationSchedule] add failed identifier=\(identifier) fireDate=\(fireDate): \(error.localizedDescription)")
        }
    }

    private func deliverMissedNotification(for candidate: ReminderCandidate, missedDate: Date) async -> Bool {
        let baseIdentifier = requestIdentifier(ownerKind: candidate.ownerKind, ownerId: candidate.ownerId)
        let identifier = "\(baseIdentifier).missed"
        let request = makeRequest(
            identifier: identifier,
            candidate: candidate,
            fireDate: missedDate,
            trigger: nil
        )
        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            print("[NotificationSchedule] missed add failed identifier=\(identifier) fireDate=\(missedDate): \(error.localizedDescription)")
            return false
        }
    }

    private func makeRequest(
        identifier: String,
        candidate: ReminderCandidate,
        fireDate: Date,
        trigger: UNNotificationTrigger?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.project.title
        content.body = "\(candidate.body)\n\(formatFireDateString(fireDate))"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "ownerId": candidate.ownerId.uuidString,
            "ownerKind": candidate.ownerKind.rawValue,
            "projectId": candidate.project.projectId.uuidString,
            "fireTimestamp": fireDate.timeIntervalSince1970
        ]
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func calendarTrigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        var components = Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        components.nanosecond = nil
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func registerCategories() {
        let language = effectiveLanguage
        let ignoreAction = UNNotificationAction(
            identifier: "IGNORE",
            title: AppLocalization.string("忽略", language: language),
            options: [.destructive]
        )
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_TASK",
            title: AppLocalization.string("完成", language: language),
            options: [.foreground]
        )
        notificationCenter.setCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [ignoreAction, completeAction],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
    }

    private func observeSystemWake() {
#if os(macOS)
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reconcile()
            }
        }
#endif
    }

    private func requestIdentifier(ownerKind: NotificationOwnerKind, ownerId: UUID) -> String {
        "\(Self.requestPrefix)\(ownerKind.rawValue).\(ownerId.uuidString)"
    }

    private func cancel(ownerId: UUID, ownerKind: NotificationOwnerKind, removeDelivered: Bool) {
        entries(for: ownerId).forEach { modelContext.delete($0) }
        let identifier = requestIdentifier(ownerKind: ownerKind, ownerId: ownerId)
        notificationCenter.removePendingRequests(withIdentifiers: [identifier])
        if removeDelivered {
            notificationCenter.removeDeliveredNotifications(withIdentifiers: [
                identifier,
                "\(identifier).missed"
            ])
        }
        save()
    }

    private func removeDelivered(ownerId: UUID, ownerKind: NotificationOwnerKind) {
        let identifier = requestIdentifier(ownerKind: ownerKind, ownerId: ownerId)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [
            identifier,
            "\(identifier).missed"
        ])
    }

    private func reminderCandidates() -> [ReminderCandidate] {
        allProjects().filter { !$0.isArchived }.flatMap { project -> [ReminderCandidate] in
            var result: [ReminderCandidate] = []

            if let reminder = project.reminder,
               let nextTaskTitle = project.topUnfinishedTitle {
                result.append(ReminderCandidate(
                    ownerId: project.projectId,
                    ownerKind: .project,
                    project: project,
                    body: nextStepBody(for: nextTaskTitle),
                    reminder: reminder
                ))
            }

            for milestone in project.milestones where !milestone.isCompleted {
                if let reminder = milestone.reminder {
                    result.append(ReminderCandidate(
                        ownerId: milestone.milestoneId,
                        ownerKind: .milestone,
                        project: project,
                        body: milestone.title,
                        reminder: reminder
                    ))
                }
                for subTask in milestone.subtasks where !subTask.isCompleted {
                    if let reminder = subTask.reminder {
                        result.append(ReminderCandidate(
                            ownerId: subTask.taskId,
                            ownerKind: .subtask,
                            project: project,
                            body: subTask.title,
                            reminder: reminder
                        ))
                    }
                }
            }
            return result
        }
    }

    private func isCandidateActive(_ candidate: ReminderCandidate, fireDate: Date) -> Bool {
        guard !candidate.project.isArchived,
              candidate.reminder.fireTimestamp == fireDate
        else { return false }

        switch candidate.ownerKind {
        case .project:
            return candidate.project.reminder?.reminderId == candidate.reminder.reminderId
                && candidate.project.topUnfinishedTitle != nil
        case .milestone:
            return candidate.project.milestones.contains {
                $0.milestoneId == candidate.ownerId
                    && !$0.isCompleted
                    && $0.reminder?.reminderId == candidate.reminder.reminderId
            }
        case .subtask:
            return candidate.project.milestones.flatMap(\.subtasks).contains {
                $0.taskId == candidate.ownerId
                    && !$0.isCompleted
                    && $0.reminder?.reminderId == candidate.reminder.reminderId
            }
        }
    }

    private func replaceScheduleEntry(for candidate: ReminderCandidate, fireDate: Date) {
        entries(for: candidate.ownerId).forEach { modelContext.delete($0) }
        modelContext.insert(NotificationScheduleEntry(
            ownerId: candidate.ownerId,
            ownerKind: candidate.ownerKind.rawValue,
            projectId: candidate.project.projectId,
            projectTitle: candidate.project.title,
            body: candidate.body,
            fireDate: fireDate
        ))
    }

    private func formatFireDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timePart = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "\(AppLocalization.string("今天", language: effectiveLanguage)) \(timePart)"
        }
        if calendar.isDateInYesterday(date) {
            return "\(AppLocalization.string("昨天", language: effectiveLanguage)) \(timePart)"
        }
        return AppDateFormatter.string(from: date, pattern: currentSettings?.dateFormat)
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: currentSettings?.language)
    }

    private var currentSettings: AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\AppSettings.createdAt)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
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

    private func allProjects() -> [Project] {
        (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
    }

    private func save() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            print("[NotificationSchedule] save failed: \(error.localizedDescription)")
        }
    }

    private func nextStepBody(for title: String) -> String {
        AppLocalization.format("下一步：%@", language: effectiveLanguage, title)
    }
}

private struct ReminderCandidate {
    let ownerId: UUID
    let ownerKind: NotificationOwnerKind
    let project: Project
    let body: String
    let reminder: Reminder
}

extension NotificationOwnerKind: CaseIterable {}

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
