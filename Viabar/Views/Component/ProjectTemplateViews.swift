import SwiftData
import SwiftUI

// MARK: - Project Template Management

struct ProjectTemplateManagementView: View {
    @Environment(ServiceContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectTemplate.orderIndex) private var templates: [ProjectTemplate]

    @State private var showingCreateEditor = false
    @State private var editingTemplate: ProjectTemplate?
    @State private var deletingTemplate: ProjectTemplate?

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("项目模板")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showingCreateEditor = true
                } label: {
                    Image(systemName: "plus.app")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("新增模板")
            }
            .padding()

            Divider()

            if templates.isEmpty {
                ContentUnavailableView(
                    "暂无模板",
                    systemImage: "square.3.layers.3d",
                    description: Text("添加模板后，可在新建项目时快速初始化任务内容。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(templates) { template in
                            TemplateManagementRow(template: template)
                                .contextMenu {
                                    Button {
                                        editingTemplate = template
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        deletingTemplate = template
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding()
        }
        .frame(width: 470, height: 500)
        .sheet(isPresented: $showingCreateEditor) {
            ProjectTemplateEditorView()
        }
        .sheet(item: $editingTemplate) { template in
            ProjectTemplateEditorView(template: template)
        }
        .alert(
            "删除模板？",
            isPresented: Binding(
                get: { deletingTemplate != nil },
                set: { if !$0 { deletingTemplate = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let template = deletingTemplate {
                    projectService?.deleteTemplate(template)
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
}

private struct TemplateManagementRow: View {
    let template: ProjectTemplate

    var body: some View {
        let taskCount = template.milestones.count
        let subtaskCount = template.milestones.reduce(0) { $0 + $1.subtasks.count }
        HStack(spacing: 12) {
            Image(systemName: template.sfSymbolName)
                .font(.title3)
                .foregroundStyle(Color(hex: template.accentColor))
                .frame(width: 34, height: 34)
                .background(Color(hex: template.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(taskCount) 项任务 / \(subtaskCount) 项子任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(Color(hex: template.accentColor))
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Project Template Editor

private struct TemplateMilestoneDraft: Identifiable {
    let id = UUID()
    var title: String
    var subtasks: [TemplateSubTaskDraft]
}

private struct TemplateSubTaskDraft: Identifiable {
    let id = UUID()
    var title: String
}

private enum TemplateEditorField: Hashable {
    case milestone(UUID)
    case subtask(UUID)
}

struct ProjectTemplateEditorView: View {
    @Environment(ServiceContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let template: ProjectTemplate?

    @State private var templateName: String
    @State private var selectedColorHex: String
    @State private var selectedSymbol: String
    @State private var showsCompletedTasks: Bool
    @State private var milestones: [TemplateMilestoneDraft]
    @State private var showingSymbolPicker = false
    @State private var scrollTarget: TemplateEditorField?
    @FocusState private var focusedField: TemplateEditorField?

    init(template: ProjectTemplate? = nil) {
        self.template = template
        _templateName = State(initialValue: template?.name ?? "")
        _selectedColorHex = State(initialValue: template?.accentColor ?? ViabarColor.palette[0].hex)
        _selectedSymbol = State(initialValue: template?.sfSymbolName ?? commonSymbols[0])
        _showsCompletedTasks = State(initialValue: !(template?.hideCompleted ?? true))
        _milestones = State(initialValue: template?.milestones
            .sorted { $0.orderIndex < $1.orderIndex }
            .map {
                TemplateMilestoneDraft(
                    title: $0.title,
                    subtasks: $0.subtasks
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .map { TemplateSubTaskDraft(title: $0.title) }
                )
            } ?? [])
    }

    private var projectService: ProjectService? {
        container.projectService
    }

    private var isUsingCustomColor: Bool {
        !ViabarColor.palette.contains {
            $0.hex.caseInsensitiveCompare(selectedColorHex) == .orderedSame
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: selectedColorHex) },
            set: { color in
                if let hex = color.hexRGB {
                    selectedColorHex = hex
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if template == nil {
                        Text("新增模板")
                    } else {
                        Text("编辑模板")
                    }
                }
                .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nameSection
                        colorAndIconSection
                        visibilitySection
                        taskSection
                    }
                    .padding()
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTarget = nil
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { saveTemplate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 550, height: 650)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模板名称").font(.headline)
            TextField("输入模板名称", text: $templateName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var colorAndIconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("默认颜色与图标").font(.headline)
            HStack(spacing: 14) {
                Button {
                    showingSymbolPicker.toggle()
                } label: {
                    Image(systemName: selectedSymbol)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("选择默认图标")
                .popover(isPresented: $showingSymbolPicker, arrowEdge: .leading) {
                    symbolPickerPopover
                }

                HStack(spacing: 10) {
                    ForEach(ViabarColor.palette, id: \.hex) { color in
                        ColorCircle(
                            hex: color.hex,
                            name: color.name,
                            isSelected: selectedColorHex.caseInsensitiveCompare(color.hex) == .orderedSame,
                            onSelect: { selectedColorHex = color.hex }
                        )
                    }
                    CustomColorCircle(color: customColorBinding, isSelected: isUsingCustomColor)
                }
            }
        }
    }

    private var visibilitySection: some View {
        Toggle("展示已完成任务", isOn: $showsCompletedTasks)
            .toggleStyle(.checkbox)
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("任务项").font(.headline)
                Spacer()
                Button {
                    appendMilestone()
                } label: {
                    Image(systemName: "plus.app")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("添加任务")
            }

            if milestones.isEmpty {
                Text("还没有预定义任务")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, draft in
                    TemplateMilestoneEditorRow(
                        milestone: binding(for: draft.id),
                        canMoveUp: index > 0,
                        canMoveDown: index < milestones.count - 1,
                        onMoveUp: { moveMilestone(at: index, by: -1) },
                        onMoveDown: { moveMilestone(at: index, by: 1) },
                        onDelete: { milestones.removeAll { $0.id == draft.id } },
                        onAddMilestone: { insertMilestone(after: draft.id) },
                        onAddSubTask: { appendSubTask(to: draft.id) },
                        onSubmitSubTask: { subtaskID in insertSubTask(after: subtaskID, in: draft.id) },
                        focusedField: $focusedField
                    )
                }
            }
        }
    }

    private var symbolPickerPopover: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(commonSymbols, id: \.self) { symbol in
                    Button {
                        selectedSymbol = symbol
                        showingSymbolPicker = false
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 32, height: 32)
                            .background(
                                selectedSymbol == symbol ? Color.blue.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 300, height: 250)
    }

    private func binding(for id: UUID) -> Binding<TemplateMilestoneDraft> {
        Binding(
            get: { milestones.first(where: { $0.id == id }) ?? TemplateMilestoneDraft(title: "", subtasks: []) },
            set: { updated in
                if let index = milestones.firstIndex(where: { $0.id == id }) {
                    milestones[index] = updated
                }
            }
        )
    }

    private func moveMilestone(at index: Int, by offset: Int) {
        let target = index + offset
        guard milestones.indices.contains(index), milestones.indices.contains(target) else { return }
        milestones.swapAt(index, target)
    }

    private func appendMilestone() {
        let milestone = TemplateMilestoneDraft(title: "", subtasks: [])
        milestones.append(milestone)
        focus(.milestone(milestone.id))
    }

    private func insertMilestone(after id: UUID) {
        let milestone = TemplateMilestoneDraft(title: "", subtasks: [])
        guard let index = milestones.firstIndex(where: { $0.id == id }) else {
            milestones.append(milestone)
            focus(.milestone(milestone.id))
            return
        }
        milestones.insert(milestone, at: index + 1)
        focus(.milestone(milestone.id))
    }

    private func appendSubTask(to milestoneID: UUID) {
        guard let index = milestones.firstIndex(where: { $0.id == milestoneID }) else { return }
        let subtask = TemplateSubTaskDraft(title: "")
        milestones[index].subtasks.append(subtask)
        focus(.subtask(subtask.id))
    }

    private func insertSubTask(after subtaskID: UUID, in milestoneID: UUID) {
        guard let milestoneIndex = milestones.firstIndex(where: { $0.id == milestoneID }) else { return }
        let subtask = TemplateSubTaskDraft(title: "")
        if let index = milestones[milestoneIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) {
            milestones[milestoneIndex].subtasks.insert(subtask, at: index + 1)
        } else {
            milestones[milestoneIndex].subtasks.append(subtask)
        }
        focus(.subtask(subtask.id))
    }

    private func focus(_ field: TemplateEditorField) {
        DispatchQueue.main.async {
            scrollTarget = field
            focusedField = field
        }
    }

    private func saveTemplate() {
        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let content = milestones.compactMap { milestone -> (title: String, subtasks: [String])? in
            let title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let subtasks = milestone.subtasks.compactMap { subtask -> String? in
                let title = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            return (title, subtasks)
        }

        _ = projectService?.saveTemplate(
            template,
            name: trimmedName,
            hideCompleted: !showsCompletedTasks,
            accentColor: selectedColorHex,
            sfSymbolName: selectedSymbol,
            milestones: content
        )
        dismiss()
    }
}

private struct TemplateMilestoneEditorRow: View {
    @Binding var milestone: TemplateMilestoneDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onAddMilestone: () -> Void
    let onAddSubTask: () -> Void
    let onSubmitSubTask: (UUID) -> Void
    var focusedField: FocusState<TemplateEditorField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("任务名称", text: $milestone.title)
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedField, equals: .milestone(milestone.id))
                    .onSubmit(onAddMilestone)
                    .id(TemplateEditorField.milestone(milestone.id))
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDown)
                Button(action: onAddSubTask) {
                    Image(systemName: "list.bullet.indent")
                }
                .buttonStyle(.plain)
                .help("添加子任务")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(milestone.subtasks.enumerated()), id: \.element.id) { index, subtask in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.tertiary)
                    TextField("子任务名称", text: subtaskBinding(for: subtask.id))
                        .textFieldStyle(.roundedBorder)
                        .focused(focusedField, equals: .subtask(subtask.id))
                        .onSubmit {
                            onSubmitSubTask(subtask.id)
                        }
                    Button {
                        moveSubtask(at: index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    Button {
                        moveSubtask(at: index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == milestone.subtasks.count - 1)
                    Button(role: .destructive) {
                        milestone.subtasks.removeAll { $0.id == subtask.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 18)
                .id(TemplateEditorField.subtask(subtask.id))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private func subtaskBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { milestone.subtasks.first(where: { $0.id == id })?.title ?? "" },
            set: { title in
                if let index = milestone.subtasks.firstIndex(where: { $0.id == id }) {
                    milestone.subtasks[index].title = title
                }
            }
        )
    }

    private func moveSubtask(at index: Int, by offset: Int) {
        let target = index + offset
        guard milestone.subtasks.indices.contains(index), milestone.subtasks.indices.contains(target) else { return }
        milestone.subtasks.swapAt(index, target)
    }
}
