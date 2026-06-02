import SwiftData
import SwiftUI

struct IOSPersistentTrashView: View {
    @Environment(ServiceContainer.self) private var services
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var query = ""
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var trashService: TrashService? {
        services.trashService
    }

    private var results: [TrashItem] {
        TrashItemIndex.results(matching: query, items: trashService?.items ?? [])
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    var body: some View {
        Group {
            if results.isEmpty && trashService?.hasMoreItems != true {
                ContentUnavailableView(
                    LocalizedStringKey(query.isEmpty ? "回收站中没有内容" : "没有匹配结果"),
                    systemImage: "trash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            row(item)
                            Divider().padding(.leading, 56)
                        }

                        if trashService?.hasMoreItems == true {
                            ProgressView()
                                .padding(.vertical, 14)
                                .onAppear {
                                    trashService?.loadNextPage()
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            searchField
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.bar)
        }
        .alert("无法恢复回收站内容", isPresented: errorBinding) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(LocalizedStringKey(errorMessage ?? ""))
        }
    }

    private func row(_ item: TrashItem) -> some View {
        HStack(spacing: 11) {
            Image(systemName: item.originalProjectSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: item.originalProjectAccentColor), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayText)
                    .font(.callout)
                    .lineLimit(1)
                Text(item.displayPath(language: effectiveLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(AppDateFormatter.trashDeletionString(from: item.deletedAt, language: effectiveLanguage))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .contentShape(Rectangle())
        .contextMenu {
            Button("恢复", systemImage: "arrow.uturn.backward") {
                restore(item)
            }
            .disabled(trashService?.restoreAvailability(for: item) != .available)

            Button("复制内容", systemImage: "doc.on.doc") {
                try? trashService?.copyToPasteboard(item)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索项目、任务、子任务和备忘录", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(IOSPrototypeSurfaceStyle.inputBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14))
        .iosPrototypeInteractiveRoundedSurface(cornerRadius: 14)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
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
}
