import Foundation

enum OverviewReportSectionKind: CaseIterable, Hashable {
    case weekTodo
    case weekDone
    case monthDone
}

struct OverviewReportSection: Identifiable {
    let kind: OverviewReportSectionKind
    let cards: [OverviewReportProjectCard]

    var id: OverviewReportSectionKind { kind }

    var copyText: String {
        cards.enumerated()
            .map { index, card in
                (["\(index + 1). \(card.project.title)"] + card.copyLines)
                    .joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }
}

struct OverviewReportProjectCard: Identifiable {
    let project: Project
    let groups: [OverviewReportTaskGroup]
    let projectReminderDate: Date?

    var id: UUID { project.projectId }

    var copyLines: [String] {
        groups.flatMap { group in
            ["- \(group.title)"] + group.subtasks.map { "  - \($0.title)" }
        }
    }
}

struct OverviewReportTaskGroup: Identifiable {
    let milestoneID: UUID
    let title: String
    let subtasks: [OverviewReportSubTaskRow]
    let reminderDate: Date?

    var id: UUID { milestoneID }
}

struct OverviewReportSubTaskRow: Identifiable {
    let taskID: UUID
    let title: String
    let reminderDate: Date?

    var id: UUID { taskID }
}

// MARK: - Builder

enum OverviewReportBuilder {
    /// weekOffset: 0 = 本周, 1 = 下周   (for weekTodo)
    /// weekDoneOffset: 0 = 本周, -1 = 上周
    /// monthDoneOffset: 0 = 本月, -1 = 上月
    static func makeReport(
        projects: [Project],
        scheduleEntries: [NotificationScheduleEntry],
        weekTodoOffset: Int = 0,
        weekDoneOffset: Int = 0,
        monthDoneOffset: Int = -1,
        now: Date = Date(),
        calendar: Calendar = .current,
        weekStartDay: WeekStartDay = WeekStartDay.resolve(nil)
    ) -> [OverviewReportSection] {
        let weeklyCalendar = weekStartDay.applying(to: calendar)
        let weekTodoInterval = weekInterval(offset: weekTodoOffset, now: now, calendar: weeklyCalendar)
        let weekDoneInterval = weekInterval(offset: weekDoneOffset, now: now, calendar: weeklyCalendar)
        let monthDoneInterval = monthInterval(offset: monthDoneOffset, now: now, calendar: calendar)

        return [
            OverviewReportSection(
                kind: .weekTodo,
                cards: plannedCards(
                    from: projects,
                    scheduleEntries: scheduleEntries,
                    upToEndOf: weekTodoInterval
                )
            ),
            OverviewReportSection(
                kind: .weekDone,
                cards: completedCards(from: projects, in: weekDoneInterval)
            ),
            OverviewReportSection(
                kind: .monthDone,
                cards: completedCards(from: projects, in: monthDoneInterval)
            ),
        ]
    }

    private static func weekInterval(offset: Int, now: Date, calendar: Calendar) -> DateInterval {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return DateInterval(start: now, end: now)
        }
        guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: week.start),
              let end = calendar.date(byAdding: .weekOfYear, value: offset, to: week.end)
        else {
            return week
        }
        return DateInterval(start: start, end: end)
    }

    private static func monthInterval(offset: Int, now: Date, calendar: Calendar) -> DateInterval {
        guard let month = calendar.dateInterval(of: .month, for: now) else {
            return DateInterval(start: now, end: now)
        }
        guard let start = calendar.date(byAdding: .month, value: offset, to: month.start),
              let end = calendar.date(byAdding: .month, value: offset, to: month.end)
        else {
            return month
        }
        return DateInterval(start: start, end: end)
    }

    // MARK: - Completed Cards（不显示提醒）

    private static func completedCards(
        from projects: [Project],
        in interval: DateInterval
    ) -> [OverviewReportProjectCard] {
        sortedProjects(projects).compactMap { project in
            let groups = sortedMilestones(in: project).compactMap { milestone -> OverviewReportTaskGroup? in
                if milestone.subtasks.isEmpty {
                    guard milestone.isCompleted,
                          contains(milestone.completedAt, in: interval)
                    else { return nil }
                    return OverviewReportTaskGroup(
                        milestoneID: milestone.milestoneId,
                        title: milestone.title,
                        subtasks: [],
                        reminderDate: milestone.reminder?.displayFireDate
                    )
                }

                let subtasks = sortedSubtasks(in: milestone)
                    .filter { $0.isCompleted && contains($0.completedAt, in: interval) }
                    .map { OverviewReportSubTaskRow(taskID: $0.taskId, title: $0.title, reminderDate: $0.reminder?.displayFireDate) }
                guard !subtasks.isEmpty else { return nil }

                return OverviewReportTaskGroup(
                    milestoneID: milestone.milestoneId,
                    title: milestone.title,
                    subtasks: subtasks,
                    reminderDate: nil
                )
            }

            guard !groups.isEmpty else { return nil }
            return OverviewReportProjectCard(project: project, groups: groups, projectReminderDate: nil)
        }
    }

    // MARK: - Planned (Todo) Cards — 截止到指定周末的所有未完成任务（含未创建通知条目的有提醒任务）

    private static func plannedCards(
        from projects: [Project],
        scheduleEntries: [NotificationScheduleEntry],
        upToEndOf interval: DateInterval
    ) -> [OverviewReportProjectCard] {
        let endDate = interval.end

        return sortedProjects(projects.filter { !$0.isArchived }).compactMap { project in
            let groups = plannedGroups(for: project, scheduleEntries: scheduleEntries, upToEndOf: endDate)
            guard !groups.isEmpty else { return nil }
            return OverviewReportProjectCard(project: project, groups: groups, projectReminderDate: project.reminder?.displayFireDate)
        }
    }

    private static func plannedGroups(
        for project: Project,
        scheduleEntries: [NotificationScheduleEntry],
        upToEndOf endDate: Date
    ) -> [OverviewReportTaskGroup] {
        var milestoneIDs = Set<UUID>()
        var subtaskIDs = Set<UUID>()

        // 从通知条目中收集
        for entry in scheduleEntries where entry.projectId == project.projectId && entry.fireDate <= endDate {
            switch entry.ownerKind {
            case "milestone":
                if let m = project.milestones.first(where: { $0.milestoneId == entry.ownerId }), !m.isCompleted {
                    milestoneIDs.insert(m.milestoneId)
                }
            case "subtask":
                if let s = project.milestones.flatMap(\.subtasks).first(where: { $0.taskId == entry.ownerId }), !s.isCompleted {
                    subtaskIDs.insert(s.taskId)
                }
            case "project":
                if let m = sortedMilestones(in: project).first(where: { !$0.isCompleted }) {
                    milestoneIDs.insert(m.milestoneId)
                    subtaskIDs.formUnion(m.subtasks.filter { !$0.isCompleted }.map(\.taskId))
                }
            default: continue
            }
        }

        // 补充：扫描所有未完成任务，只要有提醒就纳入（即使通知条目已被处理）
        for milestone in project.milestones where !milestone.isCompleted && milestone.reminder != nil {
            if let fireDate = milestone.reminder?.displayFireDate, fireDate <= endDate {
                milestoneIDs.insert(milestone.milestoneId)
            }
        }
        for milestone in project.milestones {
            for subtask in milestone.subtasks where !subtask.isCompleted && subtask.reminder != nil {
                if let fireDate = subtask.reminder?.displayFireDate, fireDate <= endDate {
                    subtaskIDs.insert(subtask.taskId)
                }
            }
        }

        return sortedMilestones(in: project).compactMap { milestone in
            let subtasks = sortedSubtasks(in: milestone)
                .filter { subtaskIDs.contains($0.taskId) }
                .map { OverviewReportSubTaskRow(
                    taskID: $0.taskId, title: $0.title,
                    reminderDate: $0.reminder?.displayFireDate
                ) }

            guard milestoneIDs.contains(milestone.milestoneId) || !subtasks.isEmpty else {
                return nil
            }

            return OverviewReportTaskGroup(
                milestoneID: milestone.milestoneId,
                title: milestone.title,
                subtasks: subtasks,
                reminderDate: milestone.reminder?.displayFireDate
            )
        }
    }

    // MARK: - Helpers

    private static func contains(_ date: Date?, in interval: DateInterval) -> Bool {
        guard let date else { return false }
        return contains(date, in: interval)
    }

    private static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static func sortedProjects(_ projects: [Project]) -> [Project] {
        projects.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.orderIndex < $1.orderIndex
        }
    }

    private static func sortedMilestones(in project: Project) -> [Milestone] {
        project.milestones.sorted { $0.orderIndex < $1.orderIndex }
    }

    private static func sortedSubtasks(in milestone: Milestone) -> [SubTask] {
        milestone.subtasks.sorted { $0.orderIndex < $1.orderIndex }
    }
}
