import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - MemoTimelineView

/// 右栏：按时间顺序展示项目备忘录，并在底部提供常驻输入框。
struct MemoTimelineView: View {
    let project: Project
    @Binding var searchDraft: String
    @Binding var activeSearchQuery: String
    var navigationRequest: GlobalSearchNavigationRequest? = nil

    @Environment(ServiceContainer.self) private var container
    @State private var newMemoContent: String = ""
    @State private var scrollToBottomTrigger = 0
    @State private var draggingMemoID: UUID?
    @State private var memoDropTarget: MemoDropTarget?
    @FocusState private var isInputFocused: Bool

    private let bottomAnchorID = "memo-bottom-anchor"
    private let inputOverlayHeight: CGFloat = 104

    private var projectService: ProjectService? {
        container.projectService
    }

    private var sortedMemos: [Memo] {
        project.memos.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
    }

    private var visibleMemos: [Memo] {
        let query = activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedMemos }

        return sortedMemos.filter {
            $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    private var hasActiveSearch: Bool {
        !activeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var targetedMemoID: UUID? {
        guard navigationRequest?.projectID == project.projectId,
              case let .some(.memo(id)) = navigationRequest?.destination
        else { return nil }
        return id
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if visibleMemos.isEmpty {
                    emptyContent
                } else {
                    memoTimeline
                }
            }

            inputBar
        }
        .background(MemoTimelineStyle.panelBackground)
    }

    // MARK: - Memo Timeline

    private var memoTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleMemos) { memo in
                        MemoCardView(memo: memo)
                            .id(memo.memoId)
                            .onDrag {
                                draggingMemoID = memo.memoId
                                return NSItemProvider(object: "memo:\(memo.memoId.uuidString)" as NSString)
                            } preview: {
                                Image(systemName: "note.text")
                                    .font(.title3)
                                    .padding(8)
                            }
                            .background {
                                GeometryReader { proxy in
                                    Color.clear
                                        .onDrop(
                                            of: [.plainText],
                                            delegate: MemoDropDelegate(
                                                targetID: memo.memoId,
                                                rowHeight: proxy.size.height,
                                                draggingMemoID: $draggingMemoID,
                                                memoDropTarget: $memoDropTarget,
                                                onMoveMemo: moveMemo(id:targetID:placement:)
                                            )
                                        )
                                }
                            }
                            .overlay(alignment: memoDropLineAlignment(for: memo.memoId)) {
                                if isMemoDropTarget(memo.memoId) {
                                    MemoDropLine()
                                }
                            }
                    }

                    Color.clear
                        .frame(height: inputOverlayHeight)
                        .id(bottomAnchorID)
                        .onDrop(
                            of: [.plainText],
                            delegate: MemoEndDropDelegate(
                                draggingMemoID: $draggingMemoID,
                                memoDropTarget: $memoDropTarget,
                                onMoveMemoToEnd: { id in
                                    projectService?.reorderMemos(in: project, movingID: id, targetID: nil, placement: .end)
                                }
                            )
                        )
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .scrollClipDisabled(false)
            .onAppear {
                if let targetedMemoID {
                    scrollToMemo(targetedMemoID, proxy: proxy)
                } else {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: scrollToBottomTrigger) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let targetedMemoID else { return }
                scrollToMemo(targetedMemoID, proxy: proxy)
            }
        }
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: hasActiveSearch ? "magnifyingglass" : "note.text.badge.plus")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text(hasActiveSearch ? "没有匹配的备忘录" : "暂无备忘录")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text(hasActiveSearch ? "重置查询后可查看全部记录" : "在下方输入框中记录项目上下文")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 104)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                ShiftReturnMemoEditor(
                    text: $newMemoContent,
                    isFocused: Binding(
                        get: { isInputFocused },
                        set: { isInputFocused = $0 }
                    ),
                    onCommit: commitMemo
                )
                .padding(.leading, 12)
                .padding(.trailing, 40)
                .padding(.vertical, 10)
                .frame(minHeight: 68, maxHeight: 68, alignment: .topLeading)

                Button(action: commitMemo) {
                    Image(systemName: "paperplane.fill")
                        .font(.callout)
                        .foregroundStyle(hasMemoDraft ? MemoTimelineStyle.sendButtonActive : MemoTimelineStyle.sendButtonInactive)
                }
                .buttonStyle(.plain)
                .disabled(!hasMemoDraft)
                .help("添加备忘录")
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MemoTimelineStyle.inputBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MemoTimelineStyle.inputBorder, lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(MemoTimelineStyle.inputPanelBackground)
        .overlay(alignment: .top) {
            MemoTimelineStyle.separator
                .frame(height: 1)
        }
    }

    // MARK: - Actions

    private func commitMemo() {
        let trimmed = newMemoContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projectService?.addMemo(to: project, content: trimmed)
        newMemoContent = ""
        isInputFocused = true
        scrollToBottomTrigger += 1
    }

    private func moveMemo(id: UUID, targetID: UUID, placement: ReorderPlacement) {
        guard id != targetID else { return }
        projectService?.reorderMemos(in: project, movingID: id, targetID: targetID, placement: placement)
    }

    private func isMemoDropTarget(_ id: UUID) -> Bool {
        if case let .memo(targetID, _) = memoDropTarget {
            return targetID == id
        }
        return false
    }

    private func memoDropLineAlignment(for id: UUID) -> Alignment {
        if case let .memo(targetID, placement) = memoDropTarget,
           targetID == id {
            return placement == .before ? .top : .bottom
        }
        return .bottom
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func scrollToMemo(_ id: UUID, proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var hasMemoDraft: Bool {
        !newMemoContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - MemoCardView

struct MemoCardView: View {
    let memo: Memo

    @Environment(ServiceContainer.self) private var container
    @State private var showsCopiedTag = false
    @State private var isCopyButtonHovered = false

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(formatTimestamp(memo.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                if showsCopiedTag {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(MemoTimelineStyle.copiedTagForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule(style: .continuous)
                                .fill(MemoTimelineStyle.copiedTagBackground)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Button {
                    copyMemoContent()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isCopyButtonHovered ? AnyShapeStyle(MemoTimelineStyle.sendButtonActive) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .help("复制备忘录")
                .onHover { hovering in
                    isCopyButtonHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }

            Text(memo.content)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MemoTimelineStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MemoTimelineStyle.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制") {
                copyMemoContent()
            }
            Divider()
            Button("删除", role: .destructive) {
                projectService?.deleteMemo(memo)
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: date))"
        }

        if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨天 \(formatter.string(from: date))"
        }

        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func copyMemoContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(memo.content, forType: .string)

        withAnimation(.easeInOut(duration: 0.12)) {
            showsCopiedTag = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                showsCopiedTag = false
            }
        }
    }
}

private enum MemoDropTarget: Equatable {
    case memo(UUID, ReorderPlacement)
}

private struct MemoDropLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .offset(x: -3)
            }
            .allowsHitTesting(false)
    }
}

private struct MemoDropDelegate: DropDelegate {
    let targetID: UUID
    let rowHeight: CGFloat
    @Binding var draggingMemoID: UUID?
    @Binding var memoDropTarget: MemoDropTarget?
    let onMoveMemo: (UUID, UUID, ReorderPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingMemoID != nil
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        memoDropTarget = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingMemoID = nil
            memoDropTarget = nil
        }

        guard let draggingMemoID,
              case let .memo(targetID, placement) = memoDropTarget
        else { return false }

        onMoveMemo(draggingMemoID, targetID, placement)
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard draggingMemoID != nil else { return }
        let placement: ReorderPlacement = info.location.y < max(rowHeight / 2, 1) ? .before : .after
        memoDropTarget = .memo(targetID, placement)
    }
}

private struct MemoEndDropDelegate: DropDelegate {
    @Binding var draggingMemoID: UUID?
    @Binding var memoDropTarget: MemoDropTarget?
    let onMoveMemoToEnd: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingMemoID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingMemoID = nil
            memoDropTarget = nil
        }
        guard let draggingMemoID else { return false }
        onMoveMemoToEnd(draggingMemoID)
        return true
    }
}

// MARK: - Style

private enum MemoTimelineStyle {
    static let panelBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.10, alpha: 1)
            : NSColor(calibratedWhite: 0.94, alpha: 1)
    })

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.16, alpha: 1)
            : NSColor.white
    })

    static let cardBorder = Color(nsColor: NSColor.separatorColor).opacity(0.35)
    static let searchFieldBackground = Color(nsColor: .controlBackgroundColor)
    static let searchFieldBorder = Color(nsColor: .separatorColor).opacity(0.45)
    static let inputPanelBackground = panelBackground
    static let inputBackground = Color(nsColor: .controlBackgroundColor)
    static let inputBorder = Color(nsColor: .separatorColor).opacity(0.55)
    static let separator = Color(nsColor: .separatorColor).opacity(0.5)
    static let copiedTagForeground = Color(nsColor: NSColor.systemGreen)
    static let copiedTagBackground = Color(nsColor: NSColor.systemGreen).opacity(0.14)
    static let sendButtonActive = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 0.46, green: 0.72, blue: 1.0, alpha: 1)
            : NSColor(calibratedRed: 0.32, green: 0.68, blue: 1.0, alpha: 1)
    })
    static let sendButtonInactive = Color(nsColor: .tertiaryLabelColor)
}

// MARK: - ShiftReturnMemoEditor

private struct ShiftReturnMemoEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = MemoTextView()
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MemoTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.onCommit = onCommit

        if isFocused, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        weak var textView: MemoTextView?
        let onCommit: () -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, onCommit: @escaping () -> Void) {
            _text = text
            _isFocused = isFocused
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
        }
    }

    final class MemoTextView: NSTextView {
        var onCommit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let usesShift = event.modifierFlags.contains(.shift)

            if isReturn, !usesShift {
                onCommit?()
                return
            }

            super.keyDown(with: event)
        }
    }
}

// MARK: - Preview

#Preview {
    let project = Project(title: "示例项目")
    project.memos = [
        Memo(content: "项目初始化", createdAt: Date().addingTimeInterval(-86400)),
        Memo(content: "对接了 CloudKit 同步方案，需要注意冲突解决策略", createdAt: Date().addingTimeInterval(-3600)),
        Memo(content: "完成了数据库 schema 设计", createdAt: Date())
    ]

    return MemoTimelineView(
        project: project,
        searchDraft: .constant(""),
        activeSearchQuery: .constant("")
    )
        .frame(width: 400, height: 500)
        .environment(ServiceContainer())
}
