import Foundation

enum TodayFocusSource: Equatable {
    case rule
    case ai
}

enum TodayFocusReason: Equatable {
    case overdue
    case today
    case favorite
    case stalled(days: Int)
    case projectOrder
    case aiSuggested
}

struct TodayFocusItem: Identifiable, Equatable {
    let projectID: UUID
    let projectTitle: String
    let projectSymbolName: String
    let projectAccentColor: String
    let projectProgress: Double
    let projectOrderIndex: Int
    let taskID: UUID
    let taskKind: WidgetTaskKind
    let milestoneID: UUID
    let taskTitle: String
    let reminderDate: Date?
    let source: TodayFocusSource
    let reason: TodayFocusReason
    let latestCompletionDate: Date?

    var id: UUID { taskID }
}

protocol TodayFocusCandidateProvider {
    func candidates(
        projects: [Project],
        now: Date,
        calendar: Calendar
    ) -> [TodayFocusItem]
}

struct RuleBasedTodayFocusProvider: TodayFocusCandidateProvider {
    func candidates(
        projects: [Project],
        now: Date,
        calendar: Calendar
    ) -> [TodayFocusItem] {
        projects
            .filter { !$0.isArchived }
            .compactMap { candidate(for: $0, now: now, calendar: calendar) }
    }

    private func candidate(
        for project: Project,
        now: Date,
        calendar: Calendar
    ) -> TodayFocusItem? {
        guard let milestone = project.milestones
            .filter({ !$0.isCompleted })
            .sorted(by: {
                $0.orderIndex == $1.orderIndex
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.orderIndex < $1.orderIndex
            })
            .first
        else { return nil }

        let subtask = milestone.subtasks
            .filter { !$0.isCompleted }
            .sorted(by: {
                $0.orderIndex == $1.orderIndex
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.orderIndex < $1.orderIndex
            })
            .first
        let taskID = subtask?.taskId ?? milestone.milestoneId
        let taskKind: WidgetTaskKind = subtask == nil ? .milestone : .subTask
        let taskTitle = subtask?.title ?? milestone.title
        let reminderDate = (subtask?.reminder ?? milestone.reminder)?.displayFireDate
        let latestCompletionDate = latestCompletionDate(in: project)

        return TodayFocusItem(
            projectID: project.projectId,
            projectTitle: project.title,
            projectSymbolName: project.sfSymbolName,
            projectAccentColor: project.accentColor,
            projectProgress: project.progress,
            projectOrderIndex: project.orderIndex,
            taskID: taskID,
            taskKind: taskKind,
            milestoneID: milestone.milestoneId,
            taskTitle: taskTitle,
            reminderDate: reminderDate,
            source: .rule,
            reason: reason(
                project: project,
                reminderDate: reminderDate,
                latestCompletionDate: latestCompletionDate,
                now: now,
                calendar: calendar
            ),
            latestCompletionDate: latestCompletionDate
        )
    }

    private func latestCompletionDate(in project: Project) -> Date? {
        let milestoneDates = project.milestones.compactMap(\.completedAt)
        let subtaskDates = project.milestones.flatMap { milestone in
            milestone.subtasks.compactMap(\.completedAt)
        }
        return (milestoneDates + subtaskDates).max()
    }

    private func reason(
        project: Project,
        reminderDate: Date?,
        latestCompletionDate: Date?,
        now: Date,
        calendar: Calendar
    ) -> TodayFocusReason {
        if let reminderDate, reminderDate < now {
            return .overdue
        }
        if let reminderDate, calendar.isDate(reminderDate, inSameDayAs: now) {
            return .today
        }
        if project.isFavorite {
            return .favorite
        }
        if let latestCompletionDate {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: latestCompletionDate),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            if days >= TodayFocusEngine.stalledDayThreshold {
                return .stalled(days: days)
            }
        }
        return .projectOrder
    }
}

struct TodayFocusEngine {
    static let stalledDayThreshold = 7

    let providers: [any TodayFocusCandidateProvider]

    init(providers: [any TodayFocusCandidateProvider] = [RuleBasedTodayFocusProvider()]) {
        self.providers = providers
    }

    func items(
        projects: [Project],
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [TodayFocusItem] {
        let activeProjects: [UUID: Project] = Dictionary(
            uniqueKeysWithValues: projects
                .filter { !$0.isArchived }
                .map { ($0.projectId, $0) }
        )
        let candidates = providers.flatMap {
            $0.candidates(projects: projects, now: now, calendar: calendar)
        }
        let validCandidates: [TodayFocusItem] = candidates.compactMap { candidate -> TodayFocusItem? in
            guard let project = activeProjects[candidate.projectID] else { return nil }
            return Self.validated(candidate, in: project)
        }
        let sorted = validCandidates.sorted(by: Self.precedes)
        var seenProjects = Set<UUID>()
        let deduplicated = sorted.filter { seenProjects.insert($0.projectID).inserted }
        return Array(deduplicated.prefix(max(0, limit)))
    }

    func nextRefreshDate(
        items: [TodayFocusItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let refreshCeiling = now.addingTimeInterval(15 * 60)
        var boundaries = [refreshCeiling]

        if let midnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ), midnight > now {
            boundaries.append(midnight)
        }

        boundaries.append(contentsOf: items.compactMap(\.reminderDate).filter { $0 > now })

        for item in items {
            guard let latestCompletionDate = item.latestCompletionDate,
                  let stalledBoundary = calendar.date(
                      byAdding: .day,
                      value: Self.stalledDayThreshold,
                      to: calendar.startOfDay(for: latestCompletionDate)
                  ),
                  stalledBoundary > now
            else { continue }
            boundaries.append(stalledBoundary)
        }

        return boundaries.filter { $0 > now }.min() ?? refreshCeiling
    }

    nonisolated private static func precedes(_ lhs: TodayFocusItem, _ rhs: TodayFocusItem) -> Bool {
        let lhsRank = rank(for: lhs.reason)
        let rhsRank = rank(for: rhs.reason)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        switch (lhs.reason, rhs.reason) {
        case (.overdue, .overdue), (.today, .today):
            if lhs.reminderDate != rhs.reminderDate {
                return (lhs.reminderDate ?? .distantFuture) < (rhs.reminderDate ?? .distantFuture)
            }
        case let (.stalled(lhsDays), .stalled(rhsDays)):
            if lhsDays != rhsDays {
                return lhsDays > rhsDays
            }
        default:
            break
        }

        if lhs.projectOrderIndex != rhs.projectOrderIndex {
            return lhs.projectOrderIndex < rhs.projectOrderIndex
        }
        let titleOrder = lhs.projectTitle.localizedStandardCompare(rhs.projectTitle)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.taskID.uuidString < rhs.taskID.uuidString
    }

    private static func validated(
        _ candidate: TodayFocusItem,
        in project: Project
    ) -> TodayFocusItem? {
        guard let milestone = project.milestones.first(where: {
            $0.milestoneId == candidate.milestoneID && !$0.isCompleted
        }) else { return nil }

        let taskTitle: String
        let reminderDate: Date?
        switch candidate.taskKind {
        case .milestone:
            guard milestone.milestoneId == candidate.taskID else { return nil }
            taskTitle = milestone.title
            reminderDate = milestone.reminder?.displayFireDate
        case .subTask:
            guard let subtask = milestone.subtasks.first(where: {
                $0.taskId == candidate.taskID && !$0.isCompleted
            }) else { return nil }
            taskTitle = subtask.title
            reminderDate = subtask.reminder?.displayFireDate
        }

        let completionDates = project.milestones.compactMap(\.completedAt)
            + project.milestones.flatMap { $0.subtasks.compactMap(\.completedAt) }
        return TodayFocusItem(
            projectID: project.projectId,
            projectTitle: project.title,
            projectSymbolName: project.sfSymbolName,
            projectAccentColor: project.accentColor,
            projectProgress: project.progress,
            projectOrderIndex: project.orderIndex,
            taskID: candidate.taskID,
            taskKind: candidate.taskKind,
            milestoneID: milestone.milestoneId,
            taskTitle: taskTitle,
            reminderDate: reminderDate,
            source: candidate.source,
            reason: candidate.reason,
            latestCompletionDate: completionDates.max()
        )
    }

    nonisolated private static func rank(for reason: TodayFocusReason) -> Int {
        switch reason {
        case .overdue: 0
        case .today: 1
        case .favorite: 2
        case .stalled: 3
        case .projectOrder: 4
        case .aiSuggested: 5
        }
    }
}
