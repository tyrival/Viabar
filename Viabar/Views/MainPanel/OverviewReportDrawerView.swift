import AppKit
import SwiftUI

struct OverviewReportDrawerView: View {
    let report: OverviewReport
    let onToggleVisibility: () -> Void

    @State private var copiedKind: OverviewReportSectionKind?
    @State private var hoveredCopyKind: OverviewReportSectionKind?
    @State private var isToggleHovered = false

    private let buttonSize: CGFloat = 36
    private let edgeInset: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                toggleButton
            }
            .padding(.trailing, edgeInset)
            .frame(height: buttonSize + edgeInset * 2)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(report.sections) { section in
                        Divider()
                        OverviewReportSectionView(
                            section: section,
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OverviewReportDrawerStyle.panelBackground)
    }

    private var toggleButton: some View {
        Button(action: onToggleVisibility) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(OverviewReportDrawerStyle.toggleBackground(isHovered: isToggleHovered))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("收起汇总面板")
        .onHover { isToggleHovered = $0 }
    }

    private func copy(_ section: OverviewReportSection) {
        guard !section.copyText.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.copyText, forType: .string)

        withAnimation(.easeInOut(duration: 0.12)) {
            copiedKind = section.kind
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                if copiedKind == section.kind {
                    copiedKind = nil
                }
            }
        }
    }

    private func setCopyHover(
        _ hovering: Bool,
        for kind: OverviewReportSectionKind,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }

        hoveredCopyKind = hovering ? kind : nil
        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

private struct OverviewReportSectionView: View {
    let section: OverviewReportSection
    let showsCopiedTag: Bool
    let isCopyButtonHovered: Bool
    let onCopy: () -> Void
    let onCopyHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if showsCopiedTag {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(OverviewReportDrawerStyle.copiedForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OverviewReportDrawerStyle.copiedBackground, in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(
                            isCopyButtonHovered
                                ? AnyShapeStyle(ViabarColor.primary)
                                : AnyShapeStyle(.tertiary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(section.cards.isEmpty)
                .help(Text(copyHelp))
                .onHover(perform: onCopyHover)
            }
            .frame(height: 22)

            if section.cards.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else {
                ForEach(section.cards) { card in
                    OverviewReportCardView(card: card)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var title: LocalizedStringKey {
        switch section.kind {
        case .thisWeek:
            return "本周完成"
        case .nextWeek:
            return "下周待办"
        case .thisMonth:
            return "本月完成"
        }
    }

    private var copyHelp: LocalizedStringKey {
        switch section.kind {
        case .thisWeek:
            return "复制本周完成"
        case .nextWeek:
            return "复制下周待办"
        case .thisMonth:
            return "复制本月完成"
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch section.kind {
        case .thisWeek:
            return "本周暂无完成内容"
        case .nextWeek:
            return "下周暂无待办提醒"
        case .thisMonth:
            return "本月暂无完成内容"
        }
    }
}

private struct OverviewReportCardView: View {
    let card: OverviewReportProjectCard

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: card.project.sfSymbolName)
                    .foregroundStyle(Color(hex: card.project.accentColor))

                Text(card.project.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ViabarColor.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if card.project.isArchived {
                    Text("已归档")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(card.groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(group.subtasks) { subtask in
                        Text(subtask.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            OverviewReportDrawerStyle.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OverviewReportDrawerStyle.cardBorder, lineWidth: 1)
        }
    }
}

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
            .overlay {
                Circle()
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
}
