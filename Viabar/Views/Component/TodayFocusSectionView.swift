import SwiftUI

struct TodayFocusSectionView: View {
    let items: [TodayFocusItem]
    let availableWidth: CGFloat
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage
    let onOpen: (TodayFocusItem) -> Void
    let onToggle: (TodayFocusItem) -> Void

    private let cardSpacing: CGFloat = 12
    private let stackedLayoutBreakpoint: CGFloat = 760

    private var usesStackedLayout: Bool {
        availableWidth < stackedLayoutBreakpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(AppLocalization.string("今日推荐", language: language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !items.isEmpty {
                    Text(AppLocalization.format("%d 项", language: language, items.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                emptyState
            } else if usesStackedLayout {
                stackedCards
            } else {
                horizontalCards
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ViabarColor.success)
            Text(AppLocalization.string("今天没有需要推进的任务", language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var horizontalCards: some View {
        let usableWidth = max(0, availableWidth - cardSpacing * 2)
        let primaryWidth = usableWidth * 0.5
        let secondaryWidth = usableWidth * 0.25

        return HStack(alignment: .top, spacing: cardSpacing) {
            if let primary = items.first {
                TodayFocusCardView(
                    item: primary,
                    isPrimary: true,
                    dateFormatPattern: dateFormatPattern,
                    language: language,
                    onOpen: { onOpen(primary) },
                    onToggle: { onToggle(primary) }
                )
                .frame(width: primaryWidth)
            }

            ForEach(Array(items.dropFirst())) { item in
                TodayFocusCardView(
                    item: item,
                    isPrimary: false,
                    dateFormatPattern: dateFormatPattern,
                    language: language,
                    onOpen: { onOpen(item) },
                    onToggle: { onToggle(item) }
                )
                .frame(width: secondaryWidth)
            }
        }
    }

    private var stackedCards: some View {
        VStack(alignment: .leading, spacing: cardSpacing) {
            if let primary = items.first {
                TodayFocusCardView(
                    item: primary,
                    isPrimary: true,
                    dateFormatPattern: dateFormatPattern,
                    language: language,
                    onOpen: { onOpen(primary) },
                    onToggle: { onToggle(primary) }
                )
                .frame(maxWidth: .infinity)
            }

            if items.count > 1 {
                HStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(Array(items.dropFirst())) { item in
                        TodayFocusCardView(
                            item: item,
                            isPrimary: false,
                            dateFormatPattern: dateFormatPattern,
                            language: language,
                            onOpen: { onOpen(item) },
                            onToggle: { onToggle(item) }
                        )
                        .frame(maxWidth: .infinity)
                    }
                    if items.count == 2 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(ViabarColor.mainPanelBackground)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
    }
}

private struct TodayFocusCardView: View {
    let item: TodayFocusItem
    let isPrimary: Bool
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage
    let onOpen: () -> Void
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var accentColor: Color {
        Color(hex: item.projectAccentColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: "circle")
                        .font(.system(size: isPrimary ? 18 : 16, weight: .medium))
                        .foregroundStyle(reasonColor)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Text(AppLocalization.string("标记为完成", language: language)))

                Text(item.taskTitle)
                    .font(isPrimary ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(isPrimary ? 2 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 8)

            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: reasonSymbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(reasonColor)
                    Text(reasonText)
                        .lineLimit(1)
                    if let reminderDate = item.reminderDate {
                        Text("·")
                        Text(AppDateFormatter.string(from: reminderDate, pattern: dateFormatPattern))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                progressRing
            }
        }
        .padding(isPrimary ? 16 : 14)
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(cardBorderGradient, lineWidth: colorScheme == .dark ? 0.8 : 0.7)
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.01) : Color.white)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.black.opacity(isHovering ? 0.65 : 0.40)
                            : Color(hex: "#0F172A").opacity(isHovering ? 0.10 : 0.05),
                        radius: isHovering ? 15 : 6,
                        x: 0,
                        y: isHovering ? 7 : 2.5
                    )

                LightGlassView()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .allowsHitTesting(false)

                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.05 : 0.02))
                        .allowsHitTesting(false)
                }
            }
        }
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
    }

    private var projectHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: item.projectSymbolName)
                .font(.system(size: 13))
                .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
            Text(item.projectTitle)
                .font(.system(size: isPrimary ? 14 : 13, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#00BBE1").opacity(0.2), lineWidth: 7)

            Circle()
                .trim(from: 0, to: min(max(item.projectProgress, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "#00BBE1"),
                            Color(hex: "#00F9D0"),
                            Color(hex: "#00BBE1")
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 28, height: 28)
    }

    private var cardBorderGradient: LinearGradient {
        LinearGradient(
            stops: colorScheme == .dark
                ? [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.white.opacity(0.24), location: 0.15),
                    .init(color: Color.white.opacity(0.24), location: 0.85),
                    .init(color: .clear, location: 1.0)
                ]
                : [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.10), location: 0.15),
                    .init(color: Color.black.opacity(0.10), location: 0.85),
                    .init(color: .clear, location: 1.0)
                ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private var reasonSymbolName: String {
        switch item.reason {
        case .overdue, .today:
            return "alarm.fill"
        case .favorite:
            return "star.fill"
        case .stalled:
            return "clock.arrow.circlepath"
        case .projectOrder:
            return "list.number"
        case .aiSuggested:
            return "sparkles"
        }
    }

    private var reasonColor: Color {
        switch item.reason {
        case .overdue:
            return .red
        case .today:
            return .orange
        case .favorite:
            return .yellow
        case .stalled:
            return .blue
        case .projectOrder:
            return accentColor
        case .aiSuggested:
            return .purple
        }
    }

    private var reasonText: String {
        switch item.reason {
        case .overdue:
            return AppLocalization.string("提醒已逾期", language: language)
        case .today:
            return AppLocalization.string("今天需要处理", language: language)
        case .favorite:
            return AppLocalization.string("收藏项目", language: language)
        case let .stalled(days):
            return AppLocalization.format("已 %d 天未推进", language: language, days)
        case .projectOrder:
            return AppLocalization.string("按项目顺序推荐", language: language)
        case .aiSuggested:
            return AppLocalization.string("AI 建议", language: language)
        }
    }
}
