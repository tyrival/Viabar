import SwiftData
import SwiftUI

struct IOSPersistentTemplateManagementView: View {
    @Environment(ServiceContainer.self) private var services
    @Query(sort: \ProjectTemplate.orderIndex) private var templates: [ProjectTemplate]
    @State private var isCreateEditorPresented = false
    @State private var editingTemplate: ProjectTemplate?
    @State private var deletingTemplate: ProjectTemplate?

    var body: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView(
                    "暂无模板",
                    systemImage: "square.3.layers.3d",
                    description: Text("添加模板后，可在新建项目时快速初始化任务内容。")
                )
            } else {
                List {
                    ForEach(templates) { template in
                        templateRow(template)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTemplate = template
                            }
                            .contextMenu {
                                Button("编辑", systemImage: "pencil") {
                                    editingTemplate = template
                                }
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    deletingTemplate = template
                                }
                            }
                            .swipeActions {
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    deletingTemplate = template
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreateEditorPresented = true
                } label: {
                    Image(systemName: "plus.app")
                }
            }
        }
        .sheet(isPresented: $isCreateEditorPresented) {
            IOSPersistentTemplateEditorView()
        }
        .sheet(item: $editingTemplate) { template in
            IOSPersistentTemplateEditorView(template: template)
        }
        .alert("删除模板？", isPresented: deletionBinding) {
            Button("删除", role: .destructive) {
                if let deletingTemplate {
                    services.projectService?.deleteTemplate(deletingTemplate)
                }
                deletingTemplate = nil
            }
            Button("取消", role: .cancel) {
                deletingTemplate = nil
            }
        } message: {
            Text("模板及其中预定义的任务将被删除。使用该模板创建的项目不会受到影响。")
        }
    }

    private func templateRow(_ template: ProjectTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: template.sfSymbolName)
                .font(.headline)
                .foregroundStyle(Color(hex: template.accentColor))
                .frame(width: 34, height: 34)
                .background(Color(hex: template.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(template.milestones.count) 项任务 / \(template.milestones.reduce(0) { $0 + $1.subtasks.count }) 项子任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { deletingTemplate != nil },
            set: { if !$0 { deletingTemplate = nil } }
        )
    }
}

private struct IOSTemplateMilestoneDraft: Identifiable {
    let id = UUID()
    var title: String
    var subtasks: [IOSTemplateSubtaskDraft]
}

private struct IOSTemplateSubtaskDraft: Identifiable {
    let id = UUID()
    var title: String
}

struct IOSPersistentTemplateEditorView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    let template: ProjectTemplate?

    @State private var name: String
    @State private var accentColor: String
    @State private var symbolName: String
    @State private var showsCompletedTasks: Bool
    @State private var milestones: [IOSTemplateMilestoneDraft]
    @State private var isSymbolPickerPresented = false

    init(template: ProjectTemplate? = nil) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _accentColor = State(initialValue: template?.accentColor ?? ViabarColor.palette[0].hex)
        _symbolName = State(initialValue: template?.sfSymbolName ?? commonSymbols[0])
        _showsCompletedTasks = State(initialValue: !(template?.hideCompleted ?? true))
        _milestones = State(initialValue: template?.milestones
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { milestone in
                IOSTemplateMilestoneDraft(
                    title: milestone.title,
                    subtasks: milestone.subtasks
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .map { IOSTemplateSubtaskDraft(title: $0.title) }
                )
            } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模板") {
                    TextField("模板名称", text: $name)
                    Toggle("展示已完成任务", isOn: $showsCompletedTasks)
                }

                Section("默认图标与主题色") {
                    Button {
                        isSymbolPickerPresented = true
                    } label: {
                        LabeledContent("图标") {
                            Image(systemName: symbolName)
                                .font(.title3)
                                .foregroundStyle(Color(hex: accentColor))
                        }
                    }
                    .foregroundStyle(.primary)

                    IOSPersistentAccentColorPicker(selection: $accentColor)
                }

                Section("任务项") {
                    ForEach($milestones) { $milestone in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("任务名称", text: $milestone.title)
                                Button(role: .destructive) {
                                    milestones.removeAll { $0.id == milestone.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach($milestone.subtasks) { $subtask in
                                HStack {
                                    Image(systemName: "arrow.turn.down.right")
                                        .foregroundStyle(.tertiary)
                                    TextField("子任务名称", text: $subtask.title)
                                    Button(role: .destructive) {
                                        milestone.subtasks.removeAll { $0.id == subtask.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.leading, 12)
                            }

                            Button("新增子任务", systemImage: "list.bullet.below.rectangle") {
                                milestone.subtasks.append(IOSTemplateSubtaskDraft(title: ""))
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    Button("新增任务", systemImage: "plus.app") {
                        milestones.append(IOSTemplateMilestoneDraft(title: "", subtasks: []))
                    }
                }
            }
            .navigationTitle(LocalizedStringKey(template == nil ? "新增模板" : "编辑模板"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .sheet(isPresented: $isSymbolPickerPresented) {
                IOSPersistentSymbolPicker(selection: $symbolName)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let content = milestones.compactMap { milestone -> (title: String, subtasks: [String])? in
            let title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let subtasks = milestone.subtasks.compactMap { subtask -> String? in
                let title = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            return (title, subtasks)
        }

        services.projectService?.saveTemplate(
            template,
            name: trimmedName,
            hideCompleted: !showsCompletedTasks,
            accentColor: accentColor,
            sfSymbolName: symbolName,
            milestones: content
        )
        dismiss()
    }
}
