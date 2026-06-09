import SwiftUI
import UniformTypeIdentifiers

struct YearlyReportView: View {
    let projects: [Project]
    let language: EffectiveAppLanguage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedYear: Int
    @State private var isExporting = false

    private let availableYears: [Int]

    init(projects: [Project], language: EffectiveAppLanguage) {
        self.projects = projects
        self.language = language
        let currentYear = Calendar.current.component(.year, from: Date())
        let firstYear = Self.firstCompletedYear(from: projects) ?? currentYear
        self.availableYears = Array(Array(firstYear...currentYear).reversed())
        self._selectedYear = State(initialValue: currentYear)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("年度报告")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: 12) {
                Text("选择年份")
                    .font(.body)
                Picker("", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .labelsHidden()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            if projectCards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("该年度没有已完成的任务")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(projectCards) { card in
                            yearlyProjectCard(card)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .frame(width: 72)
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button {
                    exportFile()
                } label: {
                    Text("导出")
                        .frame(width: 72)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(projectCards.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 520)
        .background(
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea()
        )
        .fileExporter(
            isPresented: $isExporting,
            document: YearlyReportDocument(content: reportLines.joined(separator: "\n")),
            contentType: .plainText,
            defaultFilename: defaultFilename
        ) { _ in }
    }

    private var defaultFilename: String {
        let label = AppLocalization.string("年度报告", language: language)
        return "Viabar_\(label)_\(selectedYear).md"
    }

    // MARK: - Card views

    @ViewBuilder
    private func yearlyProjectCard(_ card: YearlyProjectCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: card.sfSymbolName)
                    .foregroundStyle(Color(hex: card.accentColor))
                Text(card.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }

            ForEach(card.groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 5) {
                        Circle()
                            .fill(Color.gray.opacity(0.35))
                            .frame(width: 5, height: 5)
                        if let date = group.displayDate {
                            taskText(date: date, title: group.title, isPrimary: true)
                        } else {
                            Text(group.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }

                    ForEach(group.subtasks) { subtask in
                        HStack(alignment: .center, spacing: 5) {
                            Circle()
                                .fill(Color.gray.opacity(0.35))
                                .frame(width: 5, height: 5)
                            taskText(date: subtask.completedDate, title: subtask.title, isPrimary: false)
                        }
                        .padding(.leading, 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        }
    }

    private func taskText(date: String, title: String, isPrimary: Bool) -> Text {
        let dateText = Text("\(date) ")
            .font(.system(size: 12))
            .foregroundColor(.secondary)

        let titleText = Text(title)
            .font(.system(size: isPrimary ? 13 : 12, weight: isPrimary ? .medium : .regular))
            .foregroundColor(isPrimary ? .primary : .secondary)

        return dateText + titleText
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .quaternarySystemFill)
            : Color.white
    }

    private var cardBorderColor: Color {
        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.7 : 1)
    }

    // MARK: - Report data

    struct YearlyProjectCard: Identifiable {
        let id = UUID()
        let title: String
        let sfSymbolName: String
        let accentColor: String
        let groups: [YearlyTaskGroup]
    }

    struct YearlyTaskGroup: Identifiable {
        let id = UUID()
        let title: String
        let displayDate: String?
        let subtasks: [YearlySubtask]
    }

    struct YearlySubtask: Identifiable {
        let id = UUID()
        let title: String
        let completedDate: String
    }

    private var projectCards: [YearlyProjectCard] {
        let calendar = Calendar.current
        guard let startOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)),
              let startOfNextYear = calendar.date(from: DateComponents(year: selectedYear + 1, month: 1, day: 1))
        else { return [] }

        let interval = DateInterval(start: startOfYear, end: startOfNextYear)
        let df = Self.dateFormatter

        return projects
            .filter { project in
                project.milestones.contains { milestone in
                    if let d = milestone.completedAt, interval.contains(d) { return true }
                    return milestone.subtasks.contains { subtask in
                        if let d = subtask.completedAt, interval.contains(d) { return true }
                        return false
                    }
                }
            }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .compactMap { project in
                let groups = project.milestones
                    .sorted(by: { $0.orderIndex < $1.orderIndex })
                    .compactMap { milestone -> YearlyTaskGroup? in
                        let completedSubtasks = milestone.subtasks
                            .sorted(by: { $0.orderIndex < $1.orderIndex })
                            .filter { subtask in
                                if let d = subtask.completedAt, interval.contains(d) { return true }
                                return false
                            }
                            .map { subtask in
                                YearlySubtask(
                                    title: subtask.title,
                                    completedDate: df.string(from: subtask.completedAt!)
                                )
                            }

                        if !completedSubtasks.isEmpty {
                            let ownDate = milestone.completedAt.flatMap { interval.contains($0) ? df.string(from: $0) : nil }
                            let latestSubtaskDate = completedSubtasks.map(\.completedDate).sorted().last
                            return YearlyTaskGroup(
                                title: milestone.title,
                                displayDate: ownDate ?? latestSubtaskDate,
                                subtasks: completedSubtasks
                            )
                        }

                        if let d = milestone.completedAt, interval.contains(d) {
                            return YearlyTaskGroup(
                                title: milestone.title,
                                displayDate: df.string(from: d),
                                subtasks: []
                            )
                        }

                        return nil
                    }

                guard !groups.isEmpty else { return nil }
                return YearlyProjectCard(
                    title: project.title,
                    sfSymbolName: project.sfSymbolName,
                    accentColor: project.accentColor,
                    groups: groups
                )
            }
    }

    // MARK: - Export text

    private var reportLines: [String] {
        var lines: [String] = []
        lines.append("# \(String(selectedYear))")
        lines.append("")

        for card in projectCards {
            lines.append("## \(card.title)")
            for group in card.groups {
                if group.subtasks.isEmpty, let date = group.displayDate {
                    lines.append("- \(date) \(group.title)")
                } else if !group.subtasks.isEmpty {
                    let prefix = group.displayDate.map { "\($0) " } ?? ""
                    lines.append("- \(prefix)\(group.title)")
                    for s in group.subtasks {
                        lines.append("  - \(s.completedDate) \(s.title)")
                    }
                }
            }
            lines.append("")
        }
        return lines
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    // MARK: - Year detection

    static func firstCompletedYear(from projects: [Project]) -> Int? {
        var earliest: Date?
        for project in projects {
            for milestone in project.milestones {
                if let d = milestone.completedAt {
                    if earliest == nil || d < earliest! { earliest = d }
                }
                for subtask in milestone.subtasks {
                    if let d = subtask.completedAt {
                        if earliest == nil || d < earliest! { earliest = d }
                    }
                }
            }
        }
        guard let earliest else { return nil }
        return Calendar.current.component(.year, from: earliest)
    }

    private func exportFile() {
        isExporting = true
    }
}

// MARK: - FileDocument

struct YearlyReportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.plainText]

    let content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.content = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(content.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
