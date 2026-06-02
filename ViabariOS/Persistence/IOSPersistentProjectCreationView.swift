import SwiftData
import SwiftUI

struct IOSPersistentProjectCreationView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectTemplate.orderIndex) private var templates: [ProjectTemplate]

    @State private var title = ""
    @State private var selectedTemplateID: UUID?
    @State private var accentColor = ViabarColor.palette[0].hex
    @State private var symbolName = commonSymbols[0]
    @State private var isSymbolPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("项目") {
                    TextField("项目名称", text: $title)
                    Picker("模板", selection: $selectedTemplateID) {
                        Text("不使用模板").tag(UUID?.none)
                        ForEach(templates) { template in
                            Label(template.name, systemImage: template.sfSymbolName)
                                .tag(Optional(template.templateId))
                        }
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
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { createProject() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .sheet(isPresented: $isSymbolPickerPresented) {
                IOSPersistentSymbolPicker(selection: $symbolName)
            }
            .onChange(of: selectedTemplateID) { _, templateID in
                guard let templateID,
                      let template = templates.first(where: { $0.templateId == templateID })
                else { return }
                accentColor = template.accentColor
                symbolName = template.sfSymbolName
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createProject() {
        guard !trimmedTitle.isEmpty, let projectService = services.projectService else { return }
        let template = templates.first { $0.templateId == selectedTemplateID }
        let project = projectService.createProject(title: trimmedTitle, template: template)
        project.accentColor = accentColor
        project.sfSymbolName = symbolName
        projectService.updateProject(project)
        dismiss()
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
