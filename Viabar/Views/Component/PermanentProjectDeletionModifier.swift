import SwiftUI

struct PermanentProjectDeletionModifier: ViewModifier {
    @Binding var project: Project?
    let onDelete: (Project) -> Void
    @State private var projectAwaitingFinalConfirmation: Project?

    func body(content: Content) -> some View {
        content
            .alert("删除项目？", isPresented: firstConfirmationBinding) {
                Button("继续", role: .destructive) {
                    projectAwaitingFinalConfirmation = project
                    project = nil
                }
                Button("取消", role: .cancel) {
                    project = nil
                }
            } message: {
                if let project {
                    Text("“\(project.title)”包含 \(project.milestones.count) 条任务和 \(project.memos.count) 条备忘录。删除项目后不可恢复。")
                }
            }
            .alert("再次确认删除项目", isPresented: finalConfirmationBinding) {
                Button("确认删除", role: .destructive) {
                    guard let projectAwaitingFinalConfirmation else { return }
                    onDelete(projectAwaitingFinalConfirmation)
                    self.projectAwaitingFinalConfirmation = nil
                }
                Button("取消", role: .cancel) {
                    projectAwaitingFinalConfirmation = nil
                }
            } message: {
                Text("是否确认永久删除这个项目？")
            }
    }

    private var firstConfirmationBinding: Binding<Bool> {
        Binding(
            get: { project != nil },
            set: { if !$0 { project = nil } }
        )
    }

    private var finalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { projectAwaitingFinalConfirmation != nil },
            set: { if !$0 { projectAwaitingFinalConfirmation = nil } }
        )
    }
}

extension View {
    func permanentProjectDeletionConfirmation(
        project: Binding<Project?>,
        onDelete: @escaping (Project) -> Void
    ) -> some View {
        modifier(PermanentProjectDeletionModifier(project: project, onDelete: onDelete))
    }
}
