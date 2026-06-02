import SwiftUI

struct IOSPersistentArchiveFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let folders: [ArchiveFolder]
    let currentFolderID: UUID?
    let actionTitle: LocalizedStringKey
    let onConfirm: (ArchiveFolder) -> Void

    @State private var selectedFolderID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if rootFolders.isEmpty {
                    ContentUnavailableView(
                        "暂无归档文件夹",
                        systemImage: "folder",
                        description: Text("请先在归档页面新建文件夹")
                    )
                } else {
                    List {
                        ForEach(rootFolders, id: \.folderId) { folder in
                            IOSPersistentArchiveFolderPickerNode(
                                folder: folder,
                                level: 0,
                                selectedFolderID: $selectedFolderID,
                                expandedFolderIDs: $expandedFolderIDs
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择归档文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) { confirmSelection() }
                        .disabled(selectedFolderID == nil || selectedFolderID == currentFolderID)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var rootFolders: [ArchiveFolder] {
        folders.filter { $0.parent == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func confirmSelection() {
        guard let selectedFolderID,
              selectedFolderID != currentFolderID,
              let folder = folders.first(where: { $0.folderId == selectedFolderID })
        else { return }
        onConfirm(folder)
        dismiss()
    }
}

private struct IOSPersistentArchiveFolderPickerNode: View {
    let folder: ArchiveFolder
    let level: Int
    @Binding var selectedFolderID: UUID?
    @Binding var expandedFolderIDs: Set<UUID>

    private var isExpanded: Bool {
        expandedFolderIDs.contains(folder.folderId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    toggleExpansion()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(
                            folder.children.isEmpty
                                ? AnyShapeStyle(Color.clear)
                                : AnyShapeStyle(.secondary)
                        )
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .disabled(folder.children.isEmpty)

                Button {
                    selectedFolderID = folder.folderId
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                        Text(folder.name)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12 + CGFloat(level) * 16)
            .padding(.trailing, 12)
            .frame(height: 46)
            .background {
                if selectedFolderID == folder.folderId {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Divider()
                    .padding(.leading, 12 + CGFloat(level) * 16)
            }

            if isExpanded {
                ForEach(folder.children.sorted { $0.orderIndex < $1.orderIndex }, id: \.folderId) { child in
                    IOSPersistentArchiveFolderPickerNode(
                        folder: child,
                        level: level + 1,
                        selectedFolderID: $selectedFolderID,
                        expandedFolderIDs: $expandedFolderIDs
                    )
                }
            }
        }
    }

    private func toggleExpansion() {
        if isExpanded {
            expandedFolderIDs.remove(folder.folderId)
        } else {
            expandedFolderIDs.insert(folder.folderId)
        }
    }
}
