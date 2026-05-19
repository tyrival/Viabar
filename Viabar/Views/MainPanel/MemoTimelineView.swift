import SwiftUI
import SwiftData

// MARK: - MemoTimelineView

/// 右栏：流式备忘录时间线 + 常驻极简输入框。
/// 上部按时间倒序展示所有备忘录，
/// 下部为常驻输入栏，支持 Cmd+Enter 或点击发送。
struct MemoTimelineView: View {
    let project: Project

    @Environment(ServiceContainer.self) private var container
    @State private var newMemoContent: String = ""
    @FocusState private var isInputFocused: Bool

    private var projectService: ProjectService? {
        container.projectService
    }

    /// 按创建时间倒序排列
    private var sortedMemos: [Memo] {
        project.memos.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sortedMemos.isEmpty {
                emptyContent
            } else {
                memoTimeline
            }
            Divider()
            inputBar
        }
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("备忘录", systemImage: "note.text")
                .font(.headline)
            Spacer()
            Text("\(sortedMemos.count) 条记录")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Memo Timeline

    private var memoTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedMemos) { memo in
                        MemoCardView(memo: memo)
                            .id(memo.memoId)

                        // 时间分隔线（同日相邻 memo 之间不重复显示日期）
                        if let idx = sortedMemos.firstIndex(where: { $0.memoId == memo.memoId }),
                           idx < sortedMemos.count - 1 {
                            let next = sortedMemos[idx + 1]
                            if !Calendar.current.isDate(memo.createdAt, inSameDayAs: next.createdAt) {
                                dateSeparator(memo.createdAt)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollClipDisabled(false)
            .onAppear {
                if let first = sortedMemos.first {
                    proxy.scrollTo(first.memoId, anchor: .top)
                }
            }
        }
    }

    private func dateSeparator(_ date: Date) -> some View {
        HStack {
            VStack { Divider() }
            Text(formatDate(date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
            VStack { Divider() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "note.text.badge.plus")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("暂无备忘录")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("在下方输入框中记录项目上下文")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入备忘内容…", text: $newMemoContent, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .onSubmit {
                    commitMemo()
                }

            Button(action: commitMemo) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(newMemoContent.trimmingCharacters(in: .whitespaces).isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.blue))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(newMemoContent.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("发送 (⌘↵)")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func commitMemo() {
        let trimmed = newMemoContent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        projectService?.addMemo(to: project, content: trimmed)
        newMemoContent = ""
        isInputFocused = true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "今天"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "yyyy 年 M 月 d 日"
            return formatter.string(from: date)
        }
    }
}

// MARK: - MemoCardView

struct MemoCardView: View {
    let memo: Memo

    @Environment(ServiceContainer.self) private var container

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatTime(memo.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            Text(memo.content)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(memo.content, forType: .string)
            }
            Divider()
            Button("删除", role: .destructive) {
                projectService?.deleteMemo(memo)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let project = Project(title: "示例项目")
    project.memos = [
        Memo(content: "完成了数据库 schema 设计", createdAt: Date()),
        Memo(content: "对接了 CloudKit 同步方案，需要注意冲突解决策略", createdAt: Date().addingTimeInterval(-3600)),
        Memo(content: "项目初始化", createdAt: Date().addingTimeInterval(-86400)),
    ]

    return MemoTimelineView(project: project)
        .frame(width: 400, height: 500)
        .environment(ServiceContainer())
}
