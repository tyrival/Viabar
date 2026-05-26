import Foundation

enum OverviewReportSectionKind: CaseIterable, Hashable {
    case thisWeek
    case nextWeek
    case thisMonth
}

struct OverviewReport {
    let thisWeek: OverviewReportSection
    let nextWeek: OverviewReportSection
    let thisMonth: OverviewReportSection

    var sections: [OverviewReportSection] {
        [thisWeek, nextWeek, thisMonth]
    }
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

    var id: UUID { milestoneID }
}

struct OverviewReportSubTaskRow: Identifiable {
    let taskID: UUID
    let title: String

    var id: UUID { taskID }
}

enum OverviewReportBuilder {
    static func makeReport(
        projects: [Project],
        scheduleEntries: [NotificationScheduleEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> OverviewReport {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let month = calendar.dateInterval(of: .month, for: now),
              let nextWeekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: week.end)
        else {
            return emptyReport
        }

        let nextWeek = DateInterval(start: week.end, end: nextWeekEnd)

        return OverviewReport(
            thisWeek: section(.thisWeek, cards: completedCards(from: projects, in: week)),
            nextWeek: section(
                .nextWeek,
                cards: plannedCards(
                    from: projects,
                    scheduleEntries: scheduleEntries,
                    in: nextWeek
                )
            ),
            thisMonth: section(.thisMonth, cards: completedCards(from: projects, in: month))
        )
    }

    private static var emptyReport: OverviewReport {
        OverviewReport(
            thisWeek: section(.thisWeek, cards: []),
            nextWeek: section(.nextWeek, cards: []),
            thisMonth: section(.thisMonth, cards: [])
        )
    }

    private static func section(
        _ kind: OverviewReportSectionKind,
        cards: [OverviewReportProjectCard]
    ) -> OverviewReportSection {
        OverviewReportSection(kind: kind, cards: cards)
    }

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
                        subtasks: []
                    )
                }

                let subtasks = sortedSubtasks(in: milestone)
                    .filter { $0.isCompleted && contains($0.completedAt, in: interval) }
                    .map { OverviewReportSubTaskRow(taskID: $0.taskId, title: $0.title) }
                guard !subtasks.isEmpty else { return nil }

                return OverviewReportTaskGroup(
                    milestoneID: milestone.milestoneId,
                    title: milestone.title,
                    subtasks: subtasks
                )
            }

            guard !groups.isEmpty else { return nil }
            return OverviewReportProjectCard(project: project, groups: groups)
        }
    }

    private static func plannedCards(
        from projects: [Project],
        scheduleEntries: [NotificationScheduleEntry],
        in interval: DateInterval
    ) -> [OverviewReportProjectCard] {
        let entriesByProject = Dictionary(
            grouping: scheduleEntries.filter { contains($0.fireDate, in: interval) },
            by: \.projectId
        )

        return sortedProjects(projects.filter { !$0.isArchived }).compactMap { project in
            guard let entries = entriesByProject[project.projectId] else { return nil }

            let groups = plannedGroups(for: project, entries: entries)
            guard !groups.isEmpty else { return nil }
            return OverviewReportProjectCard(project: project, groups: groups)
        }
    }

    private static func plannedGroups(
        for project: Project,
        entries: [NotificationScheduleEntry]
    ) -> [OverviewReportTaskGroup] {
        var milestoneIDs = Set<UUID>()
        var subtaskIDs = Set<UUID>()

        for entry in entries {
            switch entry.ownerKind {
            case "milestone":
                guard let milestone = project.milestones.first(where: { $0.milestoneId == entry.ownerId }),
                      !milestone.isCompleted
                else { continue }

                milestoneIDs.insert(milestone.milestoneId)

            case "subtask":
                guard let subtask = project.milestones
                    .flatMap(\.subtasks)
                    .first(where: { $0.taskId == entry.ownerId }),
                    !subtask.isCompleted
                else { continue }

                subtaskIDs.insert(subtask.taskId)

            case "project":
                guard let milestone = sortedMilestones(in: project).first(where: { !$0.isCompleted })
                else { continue }

                milestoneIDs.insert(milestone.milestoneId)
                subtaskIDs.formUnion(
                    milestone.subtasks.filter { !$0.isCompleted }.map(\.taskId)
                )

            default:
                continue
            }
        }

        return sortedMilestones(in: project).compactMap { milestone in
            let subtasks = sortedSubtasks(in: milestone)
                .filter { subtaskIDs.contains($0.taskId) }
                .map { OverviewReportSubTaskRow(taskID: $0.taskId, title: $0.title) }

            guard milestoneIDs.contains(milestone.milestoneId) || !subtasks.isEmpty else {
                return nil
            }

            return OverviewReportTaskGroup(
                milestoneID: milestone.milestoneId,
                title: milestone.title,
                subtasks: subtasks
            )
        }
    }

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
