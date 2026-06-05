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
    @State private var displayOrderOverride: [UUID]?
    @State private var isCommittingDrop = false
    @FocusState private var isInputFocused: Bool

    private let bottomAnchorID = "memo-bottom-anchor"
    private let inputOverlayHeight: CGFloat = 104
    private let memoReorderPersistDelay: Double = 0.45

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
        guard !query.isEmpty else { return displayOrderedMemos }

        return sortedMemos.filter {
            $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayOrderedMemos: [Memo] {
        guard let displayOrderOverride else {
            return sortedMemos
        }

        var memosByID = Dictionary(uniqueKeysWithValues: sortedMemos.map { ($0.memoId, $0) })
        var orderedMemos = displayOrderOverride.compactMap { memosByID.removeValue(forKey: $0) }
        orderedMemos.append(contentsOf: sortedMemos.filter { memosByID[$0.memoId] != nil })
        return orderedMemos
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
                LazyVStack(spacing: 0) {
                    ForEach(visibleMemos, id: \.memoId) { memo in
                        MemoCardView(
                            memo: memo,
                            highlightRequestID: memo.memoId == targetedMemoID ? navigationRequest?.id : nil
                        )
                            .id(memo.memoId)
                            .opacity(draggingMemoID == memo.memoId && !isCommittingDrop ? 0.72 : 1)
                            .modifier(MemoDragModifier(
                                memoID: memo.memoId,
                                isEnabled: !hasActiveSearch,
                                draggingMemoID: $draggingMemoID,
                                displayOrderOverride: $displayOrderOverride
                            ))
                            .padding(.bottom, MemoTimelineStyle.cardSpacing)
                            .modifier(MemoCardDropModifier(
                                targetID: memo.memoId,
                                isEnabled: !hasActiveSearch,
                                draggingMemoID: $draggingMemoID,
                                onMoveMemo: moveMemo(id:targetID:placement:),
                                onCommitDisplayOrder: commitMemoDisplayOrder
                            ))
                    }

                    Color.clear
                        .frame(height: inputOverlayHeight)
                        .id(bottomAnchorID)
                        .onDrop(
                            of: [.plainText],
                            delegate: MemoEndDropDelegate(
                                draggingMemoID: $draggingMemoID,
                                onUpdateDisplayOrder: updateMemoDisplayOrder(movingID:targetID:placement:),
                                onCommitDisplayOrder: commitMemoDisplayOrder
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
            if hasActiveSearch {
                Text("没有匹配的备忘录")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Text("重置查询后可查看全部记录")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            } else {
                Text("暂无备忘录")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Text("在下方输入框中记录项目上下文")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
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
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = true }
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
        updateMemoDisplayOrder(movingID: id, targetID: targetID, placement: placement)
    }

    private func updateMemoDisplayOrder(movingID: UUID, targetID: UUID?, placement: ReorderPlacement) {
        guard !hasActiveSearch else { return }
        var items = displayOrderedMemos
        guard let movingIndex = items.firstIndex(where: { $0.memoId == movingID }) else {
            return
        }

        let moving = items.remove(at: movingIndex)
        let insertionIndex: Int
        if let targetID,
           let targetIndex = items.firstIndex(where: { $0.memoId == targetID }) {
            insertionIndex = placement == .after ? targetIndex + 1 : targetIndex
        } else {
            insertionIndex = items.count
        }

        guard movingIndex != insertionIndex else {
            return
        }

        items.insert(moving, at: insertionIndex)
        let reorderedIDs = items.map(\.memoId)
        guard displayOrderOverride != reorderedIDs else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            displayOrderOverride = reorderedIDs
        }
    }

    private func commitMemoDisplayOrder() {
        let finalMemos = displayOrderedMemos
        isCommittingDrop = true
        draggingMemoID = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + memoReorderPersistDelay) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                for (index, memo) in finalMemos.enumerated() where memo.orderIndex != index {
                    memo.orderIndex = index
                }
            }
            projectService?.save()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                displayOrderOverride = nil
                isCommittingDrop = false
            }
        }
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
    var highlightRequestID: UUID? = nil

    @Environment(ServiceContainer.self) private var container
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var showsCopiedTag = false
    @State private var isCopyButtonHovered = false
    @State private var isEditingMemo = false
    @State private var editDraft = ""
    @State private var showsDeleteConfirmation = false
    @FocusState private var isEditFocused: Bool

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(AppDateFormatter.string(from: memo.createdAt, pattern: settingsRecords.first?.dateFormat))
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

            memoBody
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
        .searchTargetHighlight(
            triggerID: highlightRequestID,
            isActive: highlightRequestID != nil
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                beginMemoEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                copyMemoContent()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                showsDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .alert("删除备忘录？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                projectService?.deleteMemo(memo)
            }
        } message: {
            Text("这条备忘录将被移入回收站，可在回收站中恢复。")
        }
    }

    @ViewBuilder
    private var memoBody: some View {
        if isEditingMemo {
            ShiftReturnMemoEditor(
                text: $editDraft,
                isFocused: Binding(
                    get: { isEditFocused },
                    set: { isEditFocused = $0 }
                ),
                onCommit: commitMemoEdit
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 68, maxHeight: 140, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MemoTimelineStyle.inputBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MemoTimelineStyle.inputBorder, lineWidth: 1)
            }
            .onAppear {
                DispatchQueue.main.async {
                    isEditFocused = true
                }
            }
        } else {
            Text(memo.content)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    beginMemoEdit()
                }
        }
    }

    private func beginMemoEdit() {
        editDraft = memo.content
        isEditFocused = false
        isEditingMemo = true
        DispatchQueue.main.async {
            isEditFocused = true
        }
    }

    private func commitMemoEdit() {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editDraft = memo.content
            isEditingMemo = false
            return
        }

        memo.content = trimmed
        projectService?.save()
        isEditingMemo = false
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

private struct MemoDragModifier: ViewModifier {
    let memoID: UUID
    let isEnabled: Bool
    @Binding var draggingMemoID: UUID?
    @Binding var displayOrderOverride: [UUID]?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    draggingMemoID = memoID
                    displayOrderOverride = nil
                    return NSItemProvider(object: "memo:\(memoID.uuidString)" as NSString)
                } preview: {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
        } else {
            content
        }
    }
}

private struct MemoCardDropModifier: ViewModifier {
    let targetID: UUID
    let isEnabled: Bool
    @Binding var draggingMemoID: UUID?
    let onMoveMemo: (UUID, UUID, ReorderPlacement) -> Void
    let onCommitDisplayOrder: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay {
                GeometryReader { proxy in
                    Color.primary.opacity(0.001)
                        .contentShape(Rectangle())
                        .allowsHitTesting(draggingMemoID != nil)
                        .onDrop(
                            of: [.plainText],
                            delegate: MemoCardDropDelegate(
                                targetID: targetID,
                                cardHeight: proxy.size.height,
                                draggingMemoID: $draggingMemoID,
                                onMoveMemo: onMoveMemo,
                                onCommitDisplayOrder: onCommitDisplayOrder
                            )
                        )
                }
            }
        } else {
            content
        }
    }
}

private struct MemoCardDropDelegate: DropDelegate {
    let targetID: UUID
    let cardHeight: CGFloat
    @Binding var draggingMemoID: UUID?
    let onMoveMemo: (UUID, UUID, ReorderPlacement) -> Void
    let onCommitDisplayOrder: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingMemoID != nil
    }

    func dropEntered(info: DropInfo) {
        updateDisplayOrder(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDisplayOrder(info: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingMemoID != nil else { return false }

        updateDisplayOrder(info: info)
        onCommitDisplayOrder()
        return true
    }

    private func updateDisplayOrder(info: DropInfo) {
        guard let draggingMemoID, draggingMemoID != targetID else { return }
        let placement: ReorderPlacement = info.location.y < cardHeight / 2 ? .before : .after
        onMoveMemo(draggingMemoID, targetID, placement)
    }
}

private struct MemoEndDropDelegate: DropDelegate {
    @Binding var draggingMemoID: UUID?
    let onUpdateDisplayOrder: (UUID, UUID?, ReorderPlacement) -> Void
    let onCommitDisplayOrder: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingMemoID != nil
    }

    func dropEntered(info: DropInfo) {
        updateDisplayOrder()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDisplayOrder()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingMemoID else { return false }
        onUpdateDisplayOrder(draggingMemoID, nil, .end)
        onCommitDisplayOrder()
        return true
    }

    private func updateDisplayOrder() {
        guard let draggingMemoID else { return }
        onUpdateDisplayOrder(draggingMemoID, nil, .end)
    }
}

// MARK: - Style

private enum MemoTimelineStyle {
    static let panelBackground = ViabarColor.mainPanelMemoBackground
    static let cardSpacing: CGFloat = 8

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.54)
            : NSColor.white
    })

    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.52, alpha: 0.36)
            : NSColor.separatorColor.withAlphaComponent(0.1)
    })
    static let searchFieldBackground = Color(nsColor: .controlBackgroundColor)
    static let searchFieldBorder = Color(nsColor: .separatorColor).opacity(0.45)
    static let inputPanelBackground = panelBackground
    static let inputBackground = ViabarColor.panelInputBackground
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

        textView.wantsFocusAtEnd = isFocused

        if isFocused, textView.window?.firstResponder !== textView {
            textView.focusAtEnd()
            DispatchQueue.main.async {
                textView.focusAtEnd()
            }
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
        var wantsFocusAtEnd = false

        func focusAtEnd() {
            guard let window else {
                wantsFocusAtEnd = true
                return
            }
            window.makeFirstResponder(self)
            setSelectedRange(NSRange(location: string.count, length: 0))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard wantsFocusAtEnd else { return }
            DispatchQueue.main.async { [weak self] in
                self?.focusAtEnd()
            }
        }

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
        .modelContainer(for: AppSettings.self, inMemory: true)
}
