import SwiftUI

struct GlobalSearchOverlay: View {
    @Binding var isPresented: Bool
    @Binding var query: String
    @Binding var highlightedResultID: String?
    let results: [GlobalSearchResult]
    let availableWidth: CGFloat
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let onPresent: () -> Void
    let onSelect: (GlobalSearchResult) -> Void

    @FocusState private var isFieldFocused: Bool
    @State private var hoveredResultID: String?

    private let rowHeight: CGFloat = 54
    private let maximumVisibleResults: CGFloat = 8

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedResultID: String? {
        hoveredResultID ?? highlightedResultID
    }

    var body: some View {
        Group {
            if isPresented {
                expandedPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            } else {
                collapsedButton
                    .transition(.opacity)
            }
        }
        .frame(width: isPresented ? availableWidth : buttonSize, alignment: .trailing)
        .onChange(of: results.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                highlightedResultID = nil
                hoveredResultID = nil
                return
            }
            if let highlightedResultID, ids.contains(highlightedResultID) {
                return
            }
            highlightedResultID = ids.first
        }
    }

    private var collapsedButton: some View {
        Button {
            onPresent()
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: buttonSize, height: buttonSize)
                .background {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("全局搜索")
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            searchField
                .zIndex(1)

            if !trimmedQuery.isEmpty {
                Divider()
                resultContent
                    .zIndex(0)
            }
        }
        .frame(width: availableWidth, alignment: .trailing)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
        .onAppear {
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
        }
        .onKeyPress(.return) {
            activateHighlightedResult()
        }
        .onKeyPress(.escape) {
            dismiss()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索任务、子任务和备忘录", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFieldFocused)
                .onSubmit {
                    _ = activateHighlightedResult()
                }

            if !query.isEmpty {
                Button {
                    clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: buttonSize)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var resultContent: some View {
        if results.isEmpty {
            Text("没有匹配结果")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: rowHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            GlobalSearchResultRow(
                                result: result,
                                isSelected: selectedResultID == result.id,
                                rowHeight: rowHeight
                            )
                            .id(result.id)
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                hoveredResultID = isHovering ? result.id : nil
                            }
                            .onTapGesture {
                                onSelect(result)
                            }
                        }
                    }
                }
                .scrollClipDisabled(false)
                .onChange(of: highlightedResultID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .frame(height: min(CGFloat(results.count), maximumVisibleResults) * rowHeight)
            .clipped()
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        hoveredResultID = nil

        let currentIndex = highlightedResultID.flatMap { selectedID in
            results.firstIndex(where: { $0.id == selectedID })
        } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (currentIndex + offset + results.count) % results.count
        highlightedResultID = results[nextIndex].id
        return .handled
    }

    private func activateHighlightedResult() -> KeyPress.Result {
        guard let id = highlightedResultID,
              let result = results.first(where: { $0.id == id })
        else { return .handled }
        onSelect(result)
        return .handled
    }

    private func dismiss() -> KeyPress.Result {
        clearQuery()
        isPresented = false
        isFieldFocused = false
        return .handled
    }

    private func clearQuery() {
        query = ""
        highlightedResultID = nil
        hoveredResultID = nil
        isFieldFocused = true
    }
}

private struct GlobalSearchResultRow: View {
    let result: GlobalSearchResult
    let isSelected: Bool
    let rowHeight: CGFloat

    private var foreground: Color {
        isSelected ? .white : .primary
    }

    private var secondaryForeground: Color {
        isSelected ? .white.opacity(0.84) : .secondary
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: result.project.sfSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: result.project.accentColor))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(result.text)
                    .font(.callout)
                    .foregroundStyle(foreground)
                    .lineLimit(1)

                Text(result.path)
                    .font(.caption)
                    .foregroundStyle(secondaryForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(isSelected ? ViabarColor.primary : .clear)
    }
}
