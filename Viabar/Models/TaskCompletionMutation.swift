import Foundation

enum TaskCompletionMutation {
    static func toggle(_ milestone: Milestone, now: Date = Date()) {
        if milestone.subtasks.isEmpty {
            milestone.isCompleted.toggle()
            milestone.completedAt = milestone.isCompleted ? now : nil
            return
        }

        let target = !milestone.isCompleted
        let completedAt = target ? now : nil
        for subtask in milestone.subtasks {
            subtask.isCompleted = target
            subtask.completedAt = completedAt
        }
        milestone.isCompleted = target
        milestone.completedAt = completedAt
    }

    static func toggle(_ subtask: SubTask, now: Date = Date()) {
        subtask.isCompleted.toggle()
        subtask.completedAt = subtask.isCompleted ? now : nil
        subtask.milestone?.syncCompletionFromSubtasks()
    }
}
