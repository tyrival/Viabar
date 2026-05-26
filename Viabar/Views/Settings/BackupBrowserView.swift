import SwiftUI

struct BackupBrowserView: View {
    let backupService: BackupService
    let settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selectedBackup: BackupFileMetadata?
    @State private var showsFirstConfirmation = false
    @State private var showsFinalConfirmation = false
    @State private var showsRestoreFailure = false

    private var language: EffectiveAppLanguage {
        EffectiveAppLanguage.resolve(locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("可用的备份：")
                .font(.headline)

            backupList

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("恢复") {
                    showsFirstConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedBackup == nil)
            }
        }
        .padding(20)
        .frame(width: 510, height: 420)
        .onAppear {
            try? backupService.refreshBackups(settings: settings)
        }
        .alert("恢复当前备份？", isPresented: $showsFirstConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive) {
                showsFinalConfirmation = true
            }
        } message: {
            Text("恢复将覆盖当前所有项目、归档、模板、提醒和个人设置。")
        }
        .alert("再次确认恢复", isPresented: $showsFinalConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认恢复", role: .destructive) {
                restoreSelectedBackup()
            }
        } message: {
            Text("此操作不可撤销。只有恢复其他备份才能找回当前数据。")
        }
        .alert("无法恢复备份", isPresented: $showsRestoreFailure) {
            Button("好", role: .cancel) {}
        } message: {
            Text("备份文件已损坏、不可读取或版本不受支持。当前数据未被修改。")
        }
    }

    private var backupList: some View {
        List(selection: $selectedBackup) {
            ForEach(Array(backupService.availableBackups.enumerated()), id: \.element.id) { index, backup in
                HStack {
                    Text(dayLabel(for: backup, index: index))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timeLabel(for: backup.createdAt))
                        .frame(width: 100, alignment: .leading)
                }
                .tag(backup)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }

    private func dayLabel(for backup: BackupFileMetadata, index: Int) -> String {
        if index > 0,
           Calendar.current.isDate(backup.createdAt, inSameDayAs: backupService.availableBackups[index - 1].createdAt) {
            return ""
        }
        if Calendar.current.isDateInToday(backup.createdAt) {
            return AppLocalization.string("今天", language: language)
        }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .full
        return formatter.string(from: backup.createdAt)
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func restoreSelectedBackup() {
        guard let selectedBackup else { return }
        do {
            try backupService.restore(file: selectedBackup, settings: settings)
            dismiss()
        } catch {
            showsRestoreFailure = true
        }
    }
}
