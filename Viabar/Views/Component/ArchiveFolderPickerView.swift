import SwiftUI
import SwiftData

// MARK: - ArchiveFolderPickerView

/// 归档文件夹选择弹窗 —— 右键"归档"时弹出，
/// 显示文件夹树，用户选择归档目标。
struct ArchiveFolderPickerView: View {
    let project: Project
    let onConfirm: (ArchiveFolder) -> Void
    let onCancel: () -> Void

    @Environment(ServiceContainer.self) private var container
    @Environment(\.locale) private var locale
    @Query(sort: \ArchiveFolder.orderIndex) private var allFolders: [ArchiveFolder]

    @State private var selectedFolderId: UUID?
    @State private var newSubfolderName: String = ""
    @State private var creatingInFolderId: UUID?

    private var projectService: ProjectService? {
        container.projectService
    }

    private var rootFolders: [ArchiveFolder] {
        allFolders.filter { $0.parent == nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("归档「\(project.title)」")
                    .font(.headline)
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // 文件夹树
            if rootFolders.isEmpty {
                emptyState
            } else {
                folderTreeList
            }

            Divider()

            // 底部按钮
            HStack {
                Button(action: createRootFolder) {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                        .font(.callout)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("归档", action: confirmSelection)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFolderId == nil)
            }
            .padding()
        }
        .frame(width: 360, height: 420)
    }

    // MARK: - Folder Tree

    private var folderTreeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rootFolders) { folder in
                    FolderTreeRow(
                        folder: folder,
                        selectedFolderId: $selectedFolderId,
                        creatingInFolderId: $creatingInFolderId,
                        newSubfolderName: $newSubfolderName,
                        onCreateSubfolder: createSubfolder,
                        level: 0
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("暂无归档文件夹")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("创建默认文件夹", action: createRootFolder)
                .buttonStyle(.borderless)
            Spacer()
        }
    }

    // MARK: - Actions

    private func confirmSelection() {
        guard let id = selectedFolderId,
              let folder = allFolders.first(where: { $0.folderId == id })
        else { return }
        onConfirm(folder)
    }

    private func createRootFolder() {
        guard let svc = projectService else { return }
        let language = EffectiveAppLanguage.resolve(locale: locale)
        let folder = svc.createArchiveFolder(
            name: AppLocalization.string("默认归档", language: language)
        )
        selectedFolderId = folder.folderId
    }

    private func createSubfolder(parent: ArchiveFolder) {
        let name = newSubfolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let svc = projectService else { return }
        let sub = svc.createArchiveFolder(name: name, parent: parent)
        newSubfolderName = ""
        creatingInFolderId = nil
        selectedFolderId = sub.folderId
    }
}

// MARK: - FolderTreeRow (recursive)

struct FolderTreeRow: View {
    let folder: ArchiveFolder
    @Binding var selectedFolderId: UUID?
    @Binding var creatingInFolderId: UUID?
    @Binding var newSubfolderName: String
    let onCreateSubfolder: (ArchiveFolder) -> Void
    let level: Int

    private let indentPerLevel: CGFloat = 20

    private var isSelected: Bool {
        selectedFolderId == folder.folderId
    }

    private var isCreating: Bool {
        creatingInFolderId == folder.folderId
    }

    var body: some View {
        VStack(spacing: 0) {
            // 当前文件夹行
            Button {
                selectedFolderId = folder.folderId
            } label: {
                HStack(spacing: 8) {
                    // 缩进
                    ForEach(0..<level, id: \.self) { _ in
                        Rectangle()
                            .fill(.clear)
                            .frame(width: indentPerLevel)
                    }

                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .font(.title3)

                    Text(folder.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    // 添加子文件夹按钮
                    if isSelected {
                        Button {
                            creatingInFolderId = folder.folderId
                            newSubfolderName = ""
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("在此文件夹下新建子文件夹")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.blue.opacity(0.08)
                        : Color.clear
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 子文件夹输入框
            if isCreating {
                HStack(spacing: 8) {
                    ForEach(0...level, id: \.self) { _ in
                        Rectangle().fill(.clear).frame(width: indentPerLevel)
                    }
                    Image(systemName: "folder.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    TextField("子文件夹名称", text: $newSubfolderName)
                        .textFieldStyle(.plain)
                        .onSubmit { onCreateSubfolder(folder) }
                    Button(action: { onCreateSubfolder(folder) }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(newSubfolderName.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(ViabarColor.success))
                    }
                    .buttonStyle(.plain)
                    .disabled(newSubfolderName.isEmpty)
                    Button(action: { creatingInFolderId = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // 递归子文件夹
            let sortedChildren = folder.children.sorted { $0.orderIndex < $1.orderIndex }
            ForEach(sortedChildren) { child in
                FolderTreeRow(
                    folder: child,
                    selectedFolderId: $selectedFolderId,
                    creatingInFolderId: $creatingInFolderId,
                    newSubfolderName: $newSubfolderName,
                    onCreateSubfolder: onCreateSubfolder,
                    level: level + 1
                )
            }
        }
    }
}

// MARK: - Modifier

struct ArchiveFolderPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let project: Project
    let onConfirm: (ArchiveFolder) -> Void

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented) {
                ArchiveFolderPickerView(
                    project: project,
                    onConfirm: { folder in
                        onConfirm(folder)
                        isPresented = false
                    },
                    onCancel: { isPresented = false }
                )
            }
    }
}

extension View {
    func archiveFolderPicker(
        isPresented: Binding<Bool>,
        project: Project,
        onConfirm: @escaping (ArchiveFolder) -> Void
    ) -> some View {
        modifier(ArchiveFolderPickerModifier(
            isPresented: isPresented,
            project: project,
            onConfirm: onConfirm
        ))
    }
}

// MARK: - Preview

#Preview {
    ArchiveFolderPickerView(
        project: Project(title: "测试项目"),
        onConfirm: { _ in },
        onCancel: {}
    )
    .environment(ServiceContainer())
}
