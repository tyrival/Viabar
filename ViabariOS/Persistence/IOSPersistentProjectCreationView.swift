import SwiftData
import SwiftUI

struct IOSPersistentProjectCreationView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectTemplate.orderIndex) private var templates: [ProjectTemplate]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]

    let editingProject: Project?

    @State private var title: String
    @State private var selectedTemplateID: UUID?
    @State private var accentColor: String
    @State private var symbolName: String
    @State private var projectReminder: Reminder?
    @State private var isSymbolPickerPresented = false
    @State private var isReminderEditorPresented = false

    init(editingProject: Project? = nil) {
        self.editingProject = editingProject
        _title = State(initialValue: editingProject?.title ?? "")
        _selectedTemplateID = State(initialValue: nil)
        _accentColor = State(initialValue: editingProject?.accentColor ?? ViabarColor.palette[0].hex)
        _symbolName = State(initialValue: editingProject?.sfSymbolName ?? commonSymbols[0])
        _projectReminder = State(initialValue: Self.copyReminder(editingProject?.reminder))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("项目") {
                    HStack {
                        TextField("项目名称", text: $title)
                        Button {
                            isReminderEditorPresented = true
                        } label: {
                            Image(systemName: projectReminder == nil ? "alarm" : "alarm.fill")
                                .foregroundStyle(projectReminder == nil ? Color.secondary : .orange)
                        }
                        .buttonStyle(.plain)
                    }
                    if editingProject == nil {
                        Picker("模板", selection: $selectedTemplateID) {
                            Text("不使用模板").tag(UUID?.none)
                            ForEach(templates) { template in
                                Label(template.name, systemImage: template.sfSymbolName)
                                    .tag(Optional(template.templateId))
                            }
                        }
                    }
                }

                if let projectReminder {
                    Section("通知提醒") {
                        IOSPersistentReminderSummary(
                            reminder: projectReminder,
                            dateFormatPattern: savedDateFormat,
                            language: effectiveLanguage
                        )
                    }
                }

                Section("图标与主题色") {
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
            }
            .navigationTitle(LocalizedStringKey(editingProject == nil ? "新建项目" : "编辑项目"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(editingProject == nil ? "创建" : "保存")) { commitProject() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .sheet(isPresented: $isSymbolPickerPresented) {
                IOSPersistentSymbolPicker(selection: $symbolName)
            }
            .sheet(isPresented: $isReminderEditorPresented) {
                IOSPersistentReminderEditor(reminder: projectReminder) {
                    projectReminder = $0
                }
            }
            .onChange(of: selectedTemplateID) { _, templateID in
                guard let templateID,
                      let template = templates.first(where: { $0.templateId == templateID })
                else { return }
                accentColor = template.accentColor
                symbolName = template.sfSymbolName
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedDateFormat: String? {
        settingsRecords.first?.dateFormat
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private func commitProject() {
        guard !trimmedTitle.isEmpty, let projectService = services.projectService else { return }
        let template = editingProject == nil
            ? templates.first { $0.templateId == selectedTemplateID }
            : nil
        let project = editingProject ?? projectService.createProject(title: trimmedTitle, template: template)
        project.title = trimmedTitle
        project.accentColor = accentColor
        project.sfSymbolName = symbolName
        project.reminder = Self.copyReminder(projectReminder)
        projectService.updateProject(project)
        dismiss()
    }

    private static func copyReminder(_ reminder: Reminder?) -> Reminder? {
        guard let reminder else { return nil }
        return Reminder(
            type: reminder.type,
            fireTime: reminder.fireTime,
            fireTimestamp: reminder.fireTimestamp,
            repeatIntervalDays: reminder.repeatIntervalDays
        )
    }
}

struct IOSPersistentAccentColorPicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ViabarColor.palette, id: \.hex) { item in
                    Button {
                        selection = item.hex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: item.hex))
                                .frame(width: 30, height: 30)
                            if selection.caseInsensitiveCompare(item.hex) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct IOSPersistentSymbolPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(commonSymbols, id: \.self) { symbol in
                        Button {
                            selection = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    selection == symbol ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("选择图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
