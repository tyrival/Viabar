import Foundation

enum MenuBarReminderSource: String, Equatable {
    case milestoneReminder
    case subTaskReminder
    case projectReminder
}

struct MenuBarTaskEntry: Identifiable {
    let id: String
    let title: String
    let parentTitle: String?
    let destination: GlobalSearchDestination
    let markerColor: TaskMarkerColor?
    let source: MenuBarReminderSource?
    let reminder: Reminder?
    let fireDate: Date?
}

struct MenuBarProjectCard: Identifiable {
    var id: UUID { project.projectId }
    let project: Project
    let entries: [MenuBarTaskEntry]
}

enum MenuBarContentBuilder {
    static func cards(
        from projects: [Project],
        scope: MenuBarProjectScope,
        mode: MenuBarContentMode,
        now: Date,
        calendar: Calendar = .current
    ) -> [MenuBarProjectCard] {
        visibleProjects(from: projects, scope: scope).compactMap { project in
            let entries = mode == .currentTask
                ? currentEntries(for: project)
                : reminderEntries(for: project, now: now, calendar: calendar)
            return entries.isEmpty ? nil : MenuBarProjectCard(project: project, entries: entries)
        }
    }

    private static func visibleProjects(
        from projects: [Project],
        scope: MenuBarProjectScope
    ) -> [Project] {
        projects
            .filter { !$0.isArchived && (scope == .allProjects || $0.isFavorite) }
            .sorted {
                $0.orderIndex == $1.orderIndex
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.orderIndex < $1.orderIndex
            }
    }

    private static func currentEntries(for project: Project) -> [MenuBarTaskEntry] {
        guard let milestone = project.milestones
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .first(where: { !$0.isCompleted })
        else { return [] }

        if let subTask = milestone.subtasks
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .first(where: { !$0.isCompleted }) {
            return [entry(for: subTask, milestone: milestone, source: nil, reminder: subTask.reminder)]
        }

        return [entry(for: milestone, source: nil, reminder: milestone.reminder)]
    }

    private static func reminderEntries(
        for project: Project,
        now: Date,
        calendar: Calendar
    ) -> [MenuBarTaskEntry] {
        let endOfToday = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: now
        ) ?? now
        var entries: [MenuBarTaskEntry] = []

        for milestone in project.milestones.sorted(by: { $0.orderIndex < $1.orderIndex })
        where !milestone.isCompleted {
            if let reminder = milestone.reminder,
               let date = reminder.displayFireDate,
               date <= endOfToday {
                entries.append(entry(for: milestone, source: .milestoneReminder, reminder: reminder))
            }

            for subTask in milestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex })
            where !subTask.isCompleted {
                if let reminder = subTask.reminder,
                   let date = reminder.displayFireDate,
                   date <= endOfToday {
                    entries.append(
                        entry(for: subTask, milestone: milestone, source: .subTaskReminder, reminder: reminder)
                    )
                }
            }
        }

        if let reminder = project.reminder,
           let date = reminder.displayFireDate,
           date <= endOfToday,
           let mapped = currentEntries(for: project).first {
            entries.append(
                MenuBarTaskEntry(
                    id: "project-reminder-\(project.projectId.uuidString)",
                    title: mapped.title,
                    parentTitle: mapped.parentTitle,
                    destination: mapped.destination,
                    markerColor: mapped.markerColor,
                    source: .projectReminder,
                    reminder: reminder,
                    fireDate: date
                )
            )
        }

        return entries.sorted {
            if $0.fireDate == $1.fireDate { return $0.id < $1.id }
            return ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture)
        }
    }

    private static func entry(
        for milestone: Milestone,
        source: MenuBarReminderSource?,
        reminder: Reminder?
    ) -> MenuBarTaskEntry {
        MenuBarTaskEntry(
            id: "\(source?.rawValue ?? "current")-milestone-\(milestone.milestoneId.uuidString)",
            title: milestone.title,
            parentTitle: nil,
            destination: .milestone(milestone.milestoneId),
            markerColor: TaskMarkerColor.resolve(milestone.markerColor),
            source: source,
            reminder: reminder,
            fireDate: reminder?.displayFireDate
        )
    }

    private static func entry(
        for subTask: SubTask,
        milestone: Milestone,
        source: MenuBarReminderSource?,
        reminder: Reminder?
    ) -> MenuBarTaskEntry {
        MenuBarTaskEntry(
            id: "\(source?.rawValue ?? "current")-subtask-\(subTask.taskId.uuidString)",
            title: subTask.title,
            parentTitle: milestone.title,
            destination: .subTask(milestoneID: milestone.milestoneId, subTaskID: subTask.taskId),
            markerColor: TaskMarkerColor.resolve(subTask.markerColor),
            source: source,
            reminder: reminder,
            fireDate: reminder?.displayFireDate
        )
    }
}
