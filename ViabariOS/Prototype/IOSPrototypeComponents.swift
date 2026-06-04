import SwiftUI
import UIKit

func dismissIOSPrototypeKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

func copyIOSPrototypeText(_ text: String) {
    UIPasteboard.general.string = text
}

struct IOSPrototypeProgressRing: View {
    let progress: Double
    var size: CGFloat = 28
    var lineWidth: CGFloat = 7

    private let ringTrackColor = Color(hex: "#00BBE1").opacity(0.2)
    private let ringStartColor = Color(hex: "#00BBE1")
    private let ringEndColor = Color(hex: "#00F9D0")

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringTrackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringStartColor, ringEndColor, ringStartColor]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

enum IOSPrototypeBottomBarMetrics {
    static let controlSize: CGFloat = 50
    static let iconSize: CGFloat = 16
    static let itemSpacing: CGFloat = 2
    static let capsulePadding: CGFloat = 4
    static let capsuleContentHeight: CGFloat = controlSize - capsulePadding * 2
}

enum IOSPrototypeSurfaceStyle {
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : .white
    }

    static func inputBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemBackground)
            : .white.opacity(0.94)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(uiColor: .separator).opacity(0.72)
            : .white.opacity(0.72)
    }

    static func cardBorder(for colorScheme: ColorScheme) -> Color {
        Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.58 : 0.16)
    }

    static func selectedTabBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.16)
            : .black.opacity(0.07)
    }

    static func shadow(for colorScheme: ColorScheme) -> Color {
        .black.opacity(colorScheme == .dark ? 0.28 : 0.07)
    }
}

private struct IOSPrototypeRoundedInteractiveSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(IOSPrototypeSurfaceStyle.border(for: colorScheme), lineWidth: 1)
                }
        }
    }
}

private struct IOSPrototypeCircleInteractiveSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(IOSPrototypeSurfaceStyle.border(for: colorScheme), lineWidth: 1)
                }
        }
    }
}

private struct IOSPrototypeCapsuleInteractiveSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(IOSPrototypeSurfaceStyle.border(for: colorScheme), lineWidth: 1)
                }
        }
    }
}

private struct IOSPrototypeCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                IOSPrototypeSurfaceStyle.cardBackground(for: colorScheme),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(IOSPrototypeSurfaceStyle.cardBorder(for: colorScheme), lineWidth: 1)
            }
    }
}

extension View {
    func iosPrototypeInteractiveRoundedSurface(cornerRadius: CGFloat) -> some View {
        modifier(IOSPrototypeRoundedInteractiveSurface(cornerRadius: cornerRadius))
    }

    func iosPrototypeInteractiveCircleSurface() -> some View {
        modifier(IOSPrototypeCircleInteractiveSurface())
    }

    func iosPrototypeInteractiveCapsuleSurface() -> some View {
        modifier(IOSPrototypeCapsuleInteractiveSurface())
    }

    func iosPrototypeCardSurface(cornerRadius: CGFloat) -> some View {
        modifier(IOSPrototypeCardSurface(cornerRadius: cornerRadius))
    }
}

struct IOSPrototypeSearchOutlineHighlight: ViewModifier {
    let consume: (UUID?) -> Bool
    let triggerID: UUID?
    var cornerRadius: CGFloat = 12

    @State private var opacity = 0.0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.orange.opacity(opacity), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .task(id: triggerID) {
                guard consume(triggerID) else {
                    opacity = 0
                    return
                }
                opacity = 1
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    opacity = 0.2
                }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 0
                }
            }
    }
}

extension View {
    func iosPrototypeSearchOutlineHighlight(
        store: IOSPrototypeStore,
        triggerID: UUID?,
        cornerRadius: CGFloat = 12
    ) -> some View {
        iosPrototypeSearchOutlineHighlight(
            consume: store.consumeNavigationHighlight,
            triggerID: triggerID,
            cornerRadius: cornerRadius
        )
    }

    func iosPrototypeSearchOutlineHighlight(
        consume: @escaping (UUID?) -> Bool,
        triggerID: UUID?,
        cornerRadius: CGFloat = 12
    ) -> some View {
        modifier(IOSPrototypeSearchOutlineHighlight(consume: consume, triggerID: triggerID, cornerRadius: cornerRadius))
    }
}

enum IOSPrototypeProgressStyle {
    static let percentColor = Color(hex: "#00BBE1")
}

enum IOSPrototypeReminderStyle {
    static func color(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> Color {
        if date < now {
            return .red
        }
        if calendar.isDateInToday(date) {
            return .orange
        }
        return .gray
    }
}

struct IOSPrototypeSectionLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

struct IOSPrototypeDetailComposer: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
            }

            TextEditor(text: $text)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 3)
        }
        .frame(height: 58)
        .padding(6)
        .background(IOSPrototypeSurfaceStyle.inputBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
        .iosPrototypeInteractiveRoundedSurface(cornerRadius: 18)
        .onAppear {
            isFocused = true
        }
    }
}

struct IOSPrototypeDetachedActionButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: IOSPrototypeBottomBarMetrics.iconSize, weight: .medium))
                .frame(
                    width: IOSPrototypeBottomBarMetrics.controlSize,
                    height: IOSPrototypeBottomBarMetrics.controlSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .foregroundStyle(Color.accentColor)
        .iosPrototypeInteractiveCircleSurface()
        .shadow(color: IOSPrototypeSurfaceStyle.shadow(for: colorScheme), radius: 10, y: 4)
    }

    @Environment(\.colorScheme) private var colorScheme
}

struct IOSPrototypeCircularIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .iosPrototypeInteractiveCircleSurface()
        .shadow(color: IOSPrototypeSurfaceStyle.shadow(for: colorScheme), radius: 8, y: 3)
    }

    @Environment(\.colorScheme) private var colorScheme
}

struct IOSPrototypeHomeTabBar: View {
    @Binding var selection: IOSPrototypeHomeTab
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectedTabNamespace

    var body: some View {
        HStack(spacing: IOSPrototypeBottomBarMetrics.itemSpacing) {
            item(.overview, symbol: "square.grid.2x2", label: "总览")
            item(.reports, symbol: "checkmark.seal.fill", label: "报告")
            item(.archive, symbol: "archivebox.fill", label: "归档")
        }
        .frame(maxWidth: .infinity)
        .frame(height: IOSPrototypeBottomBarMetrics.capsuleContentHeight)
        .padding(IOSPrototypeBottomBarMetrics.capsulePadding)
        .frame(height: IOSPrototypeBottomBarMetrics.controlSize)
        .iosPrototypeInteractiveCapsuleSurface()
        .shadow(color: IOSPrototypeSurfaceStyle.shadow(for: colorScheme), radius: 10, y: 4)
    }

    private func item(_ tab: IOSPrototypeHomeTab, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: IOSPrototypeBottomBarMetrics.iconSize))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selection == tab ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: IOSPrototypeBottomBarMetrics.capsuleContentHeight)
            .background {
                if selection == tab {
                    IOSPrototypeSelectedTabIndicator(colorScheme: colorScheme)
                        .matchedGeometryEffect(id: "home-selected-tab", in: selectedTabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IOSPrototypeDetailTabBar: View {
    @Binding var selection: IOSPrototypeDetailTab
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectedTabNamespace

    var body: some View {
        HStack(spacing: IOSPrototypeBottomBarMetrics.itemSpacing) {
            item(.tasks, symbol: "checkmark.circle.fill", label: "任务")
            item(.memos, symbol: "scribble.variable", label: "备忘录")
        }
        .frame(maxWidth: .infinity)
        .frame(height: IOSPrototypeBottomBarMetrics.capsuleContentHeight)
        .padding(IOSPrototypeBottomBarMetrics.capsulePadding)
        .frame(height: IOSPrototypeBottomBarMetrics.controlSize)
        .iosPrototypeInteractiveCapsuleSurface()
        .shadow(color: IOSPrototypeSurfaceStyle.shadow(for: colorScheme), radius: 10, y: 4)
    }

    private func item(_ tab: IOSPrototypeDetailTab, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: IOSPrototypeBottomBarMetrics.iconSize))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selection == tab ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: IOSPrototypeBottomBarMetrics.capsuleContentHeight)
            .background {
                if selection == tab {
                    IOSPrototypeSelectedTabIndicator(colorScheme: colorScheme)
                        .matchedGeometryEffect(id: "detail-selected-tab", in: selectedTabNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct IOSPrototypeSelectedTabIndicator: View {
    let colorScheme: ColorScheme

    var body: some View {
        let fill = IOSPrototypeSurfaceStyle.selectedTabBackground(for: colorScheme)

        if #available(iOS 26.0, *) {
            Capsule()
                .fill(fill)
                .glassEffect(.regular.tint(fill).interactive(), in: .capsule)
                .glassEffectTransition(.matchedGeometry)
        } else {
            Capsule()
                .fill(fill)
        }
    }
}

extension Color {
    init(prototypeHex: String) {
        let value = prototypeHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)
        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
