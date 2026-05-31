import Foundation

enum WidgetTaskKind: String, Codable, Equatable {
    case milestone
    case subTask
}

enum WidgetReminderTone: Equatable {
    case overdue
    case todayPending
    case future

    static func resolve(
        fireDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> WidgetReminderTone? {
        guard let fireDate else { return nil }
        if fireDate < now { return .overdue }
        return calendar.isDate(fireDate, inSameDayAs: now) ? .todayPending : .future
    }
}

struct WidgetTaskItem: Identifiable, Equatable {
    let id: UUID
    let kind: WidgetTaskKind
    let title: String
    let isIndented: Bool
    let reminderDate: Date?
    let reminderTone: WidgetReminderTone?

    var rowCost: Int { reminderDate == nil ? 1 : 2 }
}

struct WidgetProjectContent: Equatable {
    let projectID: UUID
    let title: String
    let sfSymbolName: String
    let accentColor: String
    let progress: Double
    let visibleItems: [WidgetTaskItem]
    let hiddenItemCount: Int
}

enum WidgetContentBuilder {
    static func activeProjects(from projects: [Project]) -> [Project] {
        projects
            .filter { !$0.isArchived }
            .sorted {
                $0.orderIndex == $1.orderIndex
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.orderIndex < $1.orderIndex
            }
    }

    static func items(
        for project: Project,
        now: Date,
        calendar: Calendar = .current
    ) -> [WidgetTaskItem] {
        project.milestones
            .sorted { $0.orderIndex < $1.orderIndex }
            .flatMap { milestone -> [WidgetTaskItem] in
                guard !milestone.isCompleted else { return [] }

                let parent = item(
                    id: milestone.milestoneId,
                    kind: .milestone,
                    title: milestone.title,
                    isIndented: false,
                    reminder: milestone.reminder,
                    now: now,
                    calendar: calendar
                )
                let children = milestone.subtasks
                    .filter { !$0.isCompleted }
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .map {
                        item(
                            id: $0.taskId,
                            kind: .subTask,
                            title: $0.title,
                            isIndented: true,
                            reminder: $0.reminder,
                            now: now,
                            calendar: calendar
                        )
                    }
                return [parent] + children
            }
    }

    static func content(
        for project: Project,
        rowBudget: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> WidgetProjectContent {
        let allItems = items(for: project, now: now, calendar: calendar)
        var remaining = max(0, rowBudget)
        var visible: [WidgetTaskItem] = []

        for item in allItems {
            guard item.rowCost <= remaining else { break }
            visible.append(item)
            remaining -= item.rowCost
        }

        return WidgetProjectContent(
            projectID: project.projectId,
            title: project.title,
            sfSymbolName: project.sfSymbolName,
            accentColor: project.accentColor,
            progress: project.progress,
            visibleItems: visible,
            hiddenItemCount: allItems.count - visible.count
        )
    }

    private static func item(
        id: UUID,
        kind: WidgetTaskKind,
        title: String,
        isIndented: Bool,
        reminder: Reminder?,
        now: Date,
        calendar: Calendar
    ) -> WidgetTaskItem {
        let reminderDate = reminder?.displayFireDate
        return WidgetTaskItem(
            id: id,
            kind: kind,
            title: title,
            isIndented: isIndented,
            reminderDate: reminderDate,
            reminderTone: WidgetReminderTone.resolve(
                fireDate: reminderDate,
                now: now,
                calendar: calendar
            )
        )
    }
}
