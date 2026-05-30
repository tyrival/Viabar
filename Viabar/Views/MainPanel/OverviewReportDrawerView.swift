import AppKit
import SwiftUI

struct OverviewReportDrawerView: View {
    let sections: [OverviewReportSection]
    @Binding var weekTodoOffset: Int
    @Binding var weekDoneOffset: Int
    @Binding var monthDoneOffset: Int

    @State private var copiedKind: OverviewReportSectionKind?
    @State private var hoveredCopyKind: OverviewReportSectionKind?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部占位：保持与原来按钮行相同的高度
            Color.clear
                .frame(height: 52)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        OverviewReportSectionView(
                            section: section,
                            weekTodoOffset: $weekTodoOffset,
                            weekDoneOffset: $weekDoneOffset,
                            monthDoneOffset: $monthDoneOffset,
                            showsCopiedTag: copiedKind == section.kind,
                            isCopyButtonHovered: hoveredCopyKind == section.kind,
                            onCopy: { copy(section) },
                            onCopyHover: { hovering in
                                setCopyHover(hovering, for: section.kind, isEnabled: !section.cards.isEmpty)
                            }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OverviewReportDrawerStyle.panelBackground)
    }

    private func copy(_ section: OverviewReportSection) {
        guard !section.copyText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.copyText, forType: .string)
        withAnimation(.easeInOut(duration: 0.12)) { copiedKind = section.kind }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                if copiedKind == section.kind { copiedKind = nil }
            }
        }
    }

    private func setCopyHover(_ hovering: Bool, for kind: OverviewReportSectionKind, isEnabled: Bool) {
        guard isEnabled else { return }
        hoveredCopyKind = hovering ? kind : nil
        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}

// MARK: - Section View

private struct OverviewReportSectionView: View {
    let section: OverviewReportSection
    @Binding var weekTodoOffset: Int
    @Binding var weekDoneOffset: Int
    @Binding var monthDoneOffset: Int
    let showsCopiedTag: Bool
    let isCopyButtonHovered: Bool
    let onCopy: () -> Void
    let onCopyHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                periodPicker

                Spacer()

                if showsCopiedTag {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(OverviewReportDrawerStyle.copiedForeground)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(OverviewReportDrawerStyle.copiedBackground, in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isCopyButtonHovered ? AnyShapeStyle(ViabarColor.primary) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .disabled(section.cards.isEmpty)
                .help(Text(copyHelp))
                .onHover(perform: onCopyHover)
            }
            .frame(height: 22)

            if section.cards.isEmpty {
                Text(emptyMessage)
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else {
                ForEach(section.cards) { card in
                    OverviewReportCardView(card: card, isTodo: section.kind == .weekTodo)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var copyHelp: LocalizedStringKey {
        switch section.kind {
        case .weekTodo: return "复制周待办"
        case .weekDone: return "复制周完成"
        case .monthDone: return "复制月完成"
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch section.kind {
        case .weekTodo: return "暂无待办提醒"
        case .weekDone: return "暂无完成内容"
        case .monthDone: return "暂无完成内容"
        }
    }

    @ViewBuilder
    private var periodPicker: some View {
        switch section.kind {
        case .weekTodo:
            Picker("", selection: $weekTodoOffset) {
                Text("本周待办").tag(0)
                Text("下周待办").tag(1)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .scaleEffect(0.82)
            .offset(x: -8)

        case .weekDone:
            Picker("", selection: $weekDoneOffset) {
                Text("本周完成").tag(0)
                Text("上周完成").tag(-1)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .scaleEffect(0.82)
            .offset(x: -8)

        case .monthDone:
            Picker("", selection: $monthDoneOffset) {
                Text("本月完成").tag(0)
                Text("上月完成").tag(-1)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .scaleEffect(0.82)
            .offset(x: -8)
        }
    }
}

// MARK: - Card View

private struct OverviewReportCardView: View {
    let card: OverviewReportProjectCard
    let isTodo: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: card.project.sfSymbolName)
                    .foregroundStyle(Color(hex: card.project.accentColor))

                Text(card.project.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if isTodo, let projectReminder = card.projectReminderDate {
                    let pColor = reminderColor(projectReminder)
                    HStack(alignment: .center, spacing: 3) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(pColor)
                        Text(formatReminderDate(projectReminder))
                            .font(.system(size: 10))
                            .foregroundStyle(pColor)
                    }
                    .fixedSize()
                }

                if card.project.isFavorite, !card.project.isArchived {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ViabarColor.warning)
                }

                if card.project.isArchived {
                    Text("已归档")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(card.groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    taskRow(title: group.title, reminderDate: group.reminderDate, isPrimary: true)

                    ForEach(group.subtasks) { subtask in
                        taskRow(title: subtask.title, reminderDate: subtask.reminderDate, isPrimary: false)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(OverviewReportDrawerStyle.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OverviewReportDrawerStyle.cardBorder, lineWidth: 1)
        }
    }

    private func taskRow(title: String, reminderDate: Date?, isPrimary: Bool) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            Group {
                if let date = reminderDate {
                    let color = reminderColor(date)
                    (Text(Image(systemName: "alarm.fill")).font(.system(size: 8)).foregroundStyle(color)
                     + Text(" \(formatReminderDate(date))").font(.callout).foregroundStyle(color)
                     + Text("  \(title)").font(.callout).foregroundStyle(isPrimary ? .primary : .secondary))
                } else {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(isPrimary ? .primary : .secondary)
                }
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reminderColor(_ date: Date) -> Color {
        let now = Date()
        if date < now { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .gray
    }

    private func formatReminderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Style

private enum OverviewReportDrawerStyle {
    static let panelBackground = ViabarColor.mainPanelMemoBackground
    static let copiedForeground = Color(nsColor: .systemGreen)
    static let copiedBackground = Color(nsColor: .systemGreen).opacity(0.14)

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.54)
            : NSColor.white
    })

    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.52, alpha: 0.36)
            : NSColor.separatorColor.withAlphaComponent(0.1)
    })

    static func toggleBackground(isHovered: Bool) -> some View {
        Circle()
            .fill(ViabarColor.panelInputBackground)
            .overlay { Circle().fill(.primary.opacity(isHovered ? 0.06 : 0)) }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
}
