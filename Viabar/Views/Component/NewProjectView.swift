import SwiftUI
import SwiftData
import AppKit

// MARK: - NewProjectView

struct NewProjectView: View {
    @Environment(ServiceContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectTemplate.orderIndex) private var templates: [ProjectTemplate]

    let editingProject: Project?

    @State private var projectName: String = ""
    @State private var selectedColorHex: String = ViabarColor.palette[0].hex
    @State private var selectedSymbol: String = commonSymbols[0]
    @State private var projectReminder: Reminder?
    @State private var showingReminderPopover = false
    @State private var selectedTemplateID: UUID?
    @State private var templateSearchText = ""
    @State private var showingTemplatePicker = false
    @State private var showingTemplateManager = false
    @State private var isTemplateManagerHovered = false

    init(editingProject: Project? = nil) {
        self.editingProject = editingProject
        _projectName = State(initialValue: editingProject?.title ?? "")
        _selectedColorHex = State(initialValue: editingProject?.accentColor ?? ViabarColor.palette[0].hex)
        _selectedSymbol = State(initialValue: editingProject?.sfSymbolName ?? commonSymbols[0])
        _projectReminder = State(initialValue: Self.copyReminder(editingProject?.reminder))
    }

    private var projectService: ProjectService? {
        container.projectService
    }

    private var selectedTemplate: ProjectTemplate? {
        templates.first { $0.templateId == selectedTemplateID }
    }

    private var filteredTemplates: [ProjectTemplate] {
        let query = templateSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var isUsingCustomColor: Bool {
        !ViabarColor.palette.contains {
            $0.hex.caseInsensitiveCompare(selectedColorHex) == .orderedSame
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: selectedColorHex) },
            set: { newColor in
                if let hex = newColor.hexRGB {
                    selectedColorHex = hex
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if editingProject == nil {
                    Text("新建").font(.title3).bold()
                } else {
                    Text("编辑").font(.title3).bold()
                }
                Spacer()
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                nameField
                if editingProject == nil {
                    templateSection
                }
                iconAndColorRow
                symbolGridScroll
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                if editingProject == nil {
                    Button("创建") { commitProject() }
                        .buttonStyle(.borderedProminent)
                        .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("保存") { commitProject() }
                        .buttonStyle(.borderedProminent)
                        .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 620)
        .sheet(isPresented: $showingTemplateManager) {
            ProjectTemplateManagementView()
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("项目名称").font(.headline)
            HStack(spacing: 8) {
                TextField("输入项目名称…", text: $projectName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    showingReminderPopover.toggle()
                } label: {
                    Image(systemName: projectReminder == nil ? "alarm" : "alarm.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(projectReminder == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
                .buttonStyle(.borderless)
                .help(projectReminder == nil ? Text("添加项目提醒") : Text("编辑项目提醒"))
                .popover(isPresented: $showingReminderPopover, arrowEdge: .leading) {
                    ReminderSettingsPopover(reminder: $projectReminder)
                }
            }
        }
    }

    // MARK: - Template

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模板").font(.headline)
            HStack(spacing: 8) {
                Button {
                    showingTemplatePicker.toggle()
                } label: {
                    HStack {
                        if let selectedTemplate {
                            Image(systemName: selectedTemplate.sfSymbolName)
                                .foregroundStyle(Color(hex: selectedTemplate.accentColor))
                            Text(selectedTemplate.name)
                                .foregroundStyle(.primary)
                        } else {
                            Group {
                                if templates.isEmpty {
                                    Text("暂无模板")
                                } else {
                                    Text("选择模板...")
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingTemplatePicker, arrowEdge: .bottom) {
                    templatePickerPopover
                }

                Button {
                    showingTemplateManager = true
                } label: {
                    Image(systemName: "square.3.layers.3d.middle.filled")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(isTemplateManagerHovered ? .white : .secondary)
                        .background(
                            Circle()
                                .fill(isTemplateManagerHovered ? Color.blue : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    isTemplateManagerHovered ? Color.blue : Color(nsColor: .separatorColor).opacity(0.5),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("管理模板")
                .onHover { hovering in
                    isTemplateManagerHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }

    private var templatePickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("输入模板名称筛选", text: $templateSearchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(spacing: 4) {
                    if selectedTemplateID != nil && templateSearchText.isEmpty {
                        Button {
                            selectedTemplateID = nil
                            showingTemplatePicker = false
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .frame(width: 20)
                                Text("不使用模板")
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }

                    if filteredTemplates.isEmpty {
                        if templates.isEmpty {
                            Text("还没有模板")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("没有匹配的模板")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    } else {
                        ForEach(filteredTemplates) { template in
                            Button {
                                applyTemplateSelection(template)
                            } label: {
                                HStack {
                                    Image(systemName: template.sfSymbolName)
                                        .foregroundStyle(Color(hex: template.accentColor))
                                        .frame(width: 20)
                                    Text(template.name)
                                    Spacer()
                                    if selectedTemplateID == template.templateId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(10)
        .frame(width: 265)
    }

    private func applyTemplateSelection(_ template: ProjectTemplate) {
        selectedTemplateID = template.templateId
        selectedColorHex = template.accentColor
        selectedSymbol = template.sfSymbolName
        showingTemplatePicker = false
    }

    // MARK: - Icon & Color Row

    private var iconAndColorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("图标 & 主题色").font(.headline)
            HStack(spacing: 16) {
                // 当前选中图标
                Image(systemName: selectedSymbol)
                    .font(.title)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                // 颜色圆形
                HStack(spacing: 10) {
                    ForEach(ViabarColor.palette, id: \.hex) { item in
                        ColorCircle(
                            hex: item.hex,
                            name: item.name,
                            isSelected: selectedColorHex.caseInsensitiveCompare(item.hex) == .orderedSame,
                            onSelect: { selectedColorHex = item.hex }
                        )
                    }

                    CustomColorCircle(
                        color: customColorBinding,
                        isSelected: isUsingCustomColor
                    )
                }
            }
        }
    }

    // MARK: - Symbol Grid Scroll

    private var symbolGridScroll: some View {
        ScrollView {
            symbolGridContent
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var symbolGridContent: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(commonSymbols, id: \.self) { symbol in
                Button {
                    selectedSymbol = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.body)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(
                    selectedSymbol == symbol
                        ? Color.blue.opacity(0.15)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            selectedSymbol == symbol ? Color.blue : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Create

    private func commitProject() {
        let name = projectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let svc = projectService else { return }

        let project = editingProject ?? svc.createProject(title: name, template: selectedTemplate)
        project.title = name
        project.accentColor = selectedColorHex
        project.sfSymbolName = selectedSymbol
        project.reminder = Self.copyReminder(projectReminder)
        svc.updateProject(project)
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

// MARK: - ColorCircle

struct ColorCircle: View {
    let hex: String
    let name: LocalizedStringKey
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2).bold()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(Text(name))
    }
}

// MARK: - CustomColorCircle

struct CustomColorCircle: View {
    @Binding var color: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            ColorPicker("自定义颜色", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.01)

            Circle()
                .fill(
                    isSelected
                        ? AnyShapeStyle(color)
                        : AnyShapeStyle(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .blue, .purple, .red],
                                center: .center
                            )
                        )
                )
                .allowsHitTesting(false)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
        .help("自定义颜色")
    }
}

// MARK: - SF Symbol List (100)

let commonSymbols: [String] = [
    // 通用
    "bookmark.fill", "circle.dashed", "circle.fill", "checkmark.circle.fill", "xmark.circle.fill",
    "star.fill", "star.leadinghalf.filled", "heart.fill", "heart.circle.fill",
    "flame.fill", "bolt.fill", "bolt.circle.fill", "shield.fill",
    // 标记
    "flag.fill", "flag.checkered", "tag.fill", "pin.fill",
    "mappin.circle.fill", "location.fill", "paperclip",
    // 文件/文档
    "doc.fill", "doc.text.fill", "folder.fill", "tray.full.fill",
    "archivebox.fill", "list.bullet.clipboard.fill", "chart.bar.fill",
    "chart.pie.fill", "tablecells.fill",
    // 工具/开发
    "hammer.fill", "wrench.fill", "gearshape.fill", "gearshape.2.fill",
    "pencil.tip", "pencil.circle.fill", "keyboard.fill", "printer.fill",
    "scanner.fill", "display", "laptopcomputer", "keyboard",
    // 物体
    "cube.fill", "puzzlepiece.fill", "lightbulb.fill", "sparkles",
    "crown.fill", "rosette", "medal.fill", "graduationcap.fill",
    "building.columns.fill", "building.2.fill", "house.fill", "storefront.fill",
    // 自然/天气
    "leaf.fill", "camera.macro", "tree.fill", "sun.max.fill",
    "moon.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill",
    "snowflake", "wind", "tornado", "drop.fill",
    // 交通/出行
    "car.fill", "bus.fill", "tram.fill", "bicycle",
    "airplane", "ferry.fill", "fuelpump.fill", "figure.walk",
    // 沟通/社交
    "message.fill", "bubble.left.fill", "bubble.right.fill", "envelope.fill",
    "phone.fill", "phone.down.fill", "video.fill", "mic.fill",
    "at.circle.fill", "link.circle.fill", "person.fill", "person.2.fill",
    "person.3.fill", "figure.mind.and.body",
    // 媒体/娱乐
    "play.fill", "pause.fill", "stop.fill", "backward.fill",
    "forward.fill", "shuffle", "repeat", "music.note",
    "music.mic", "guitars.fill", "tv.fill", "film.fill",
    "gamecontroller.fill", "paintpalette.fill", "camera.fill", "photo.fill",
    // 购物/金融
    "cart.fill", "basket.fill", "creditcard.fill", "dollarsign.circle.fill",
    "yensign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill",
    "gift.fill", "bag.fill",
    // 健康/医疗
    "heart.text.square.fill", "cross.case.fill", "pills.fill", "bandage.fill",
    "stethoscope", "syringe.fill", "ear.fill", "eye.fill", "brain.head.profile",
    // 时间/日历
    "clock.fill", "alarm.fill", "stopwatch", "timer",
    "calendar", "calendar.badge.clock", "hourglass.bottomhalf.filled",
    // 其他常用
    "globe", "network", "wifi", "antenna.radiowaves.left.and.right",
    "bell.fill", "ticket.fill", "key.fill",
    "lock.fill", "lock.open.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
    "eye.slash.fill", "hand.raised.fill", "exclamationmark.triangle.fill",
    "info.circle.fill", "questionmark.circle.fill", "plus.circle.fill",
    "minus.circle.fill", "arrow.up.circle.fill", "arrow.down.circle.fill",
]

// MARK: - Preview

#Preview {
    NewProjectView()
        .environment(ServiceContainer())
        .modelContainer(
            for: [ProjectTemplate.self, TemplateMilestone.self, TemplateSubTask.self],
            inMemory: true
        )
}
