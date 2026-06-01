import SwiftData
import SwiftUI

struct TrashBrowserView: View {
    @Environment(ServiceContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var query = ""
    @State private var errorMessage: LocalizedStringKey?

    private var results: [TrashItem] {
        TrashItemIndex.results(matching: query, items: trashService?.items ?? [])
    }

    private var trashService: TrashService? {
        container.trashService
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            resultContent
        }
        .frame(width: 720, height: 520, alignment: .top)
        .environment(\.locale, effectiveLanguage.locale)
        .alert("无法恢复回收站内容", isPresented: errorBinding) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("回收站")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索项目、任务、子任务和备忘录", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var resultContent: some View {
        if results.isEmpty && trashService?.hasMoreItems != true {
            VStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("回收站中没有内容")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !query.isEmpty {
                    Text("没有匹配结果")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { item in
                        TrashResultRow(
                            item: item,
                            deletionTime: deletionTime(for: item),
                            availability: trashService?.restoreAvailability(for: item) ?? .missingProject,
                            language: effectiveLanguage,
                            onRestore: { restore(item) },
                            onCopy: { copy(item) }
                        )
                        Divider()
                    }
                    if trashService?.hasMoreItems == true {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .id(trashService?.items.count ?? 0)
                            .onAppear {
                                trashService?.loadNextPage()
                            }
                    }
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func deletionTime(for item: TrashItem) -> String {
        AppDateFormatter.trashDeletionString(
            from: item.deletedAt,
            language: effectiveLanguage
        )
    }

    private func restore(_ item: TrashItem) {
        do {
            try trashService?.restore(item)
        } catch TrashServiceError.missingProject {
            errorMessage = "原项目已不存在"
        } catch TrashServiceError.missingParentTask {
            errorMessage = "原任务已不存在"
        } catch {
            errorMessage = "无法恢复回收站内容"
        }
    }

    private func copy(_ item: TrashItem) {
        try? trashService?.copyToPasteboard(item)
    }

}

private struct TrashResultRow: View {
    let item: TrashItem
    let deletionTime: String
    let availability: TrashRestoreAvailability
    let language: EffectiveAppLanguage
    let onRestore: () -> Void
    let onCopy: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.originalProjectSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: item.originalProjectAccentColor))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayText)
                    .font(.callout)
                    .lineLimit(1)
                Text(item.displayPath(language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(deletionTime)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background {
            Rectangle()
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: onRestore) {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
                .disabled(availability != .available)
            Button(action: onCopy) {
                Label("复制内容", systemImage: "doc.on.doc")
            }
            if availability == .missingProject {
                Divider()
                Text("原项目已不存在")
            } else if availability == .missingParentTask {
                Divider()
                Text("原任务已不存在")
            }
        }
    }
}
