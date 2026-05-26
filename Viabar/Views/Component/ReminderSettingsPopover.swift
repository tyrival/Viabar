import SwiftData
import SwiftUI

struct ReminderSettingsPopover: View {
    @Binding var reminder: Reminder?
    var onReminderChange: (Reminder?) -> Void = { _ in }

    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var repeatOption: ReminderRepeatOption = .never

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 0) {
                pickerRow(icon: "calendar", title: "日期") {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(width: 250, alignment: .trailing)
                }

                Divider().padding(.leading, 40)

                pickerRow(icon: "clock", title: "时间") {
                    DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(width: 250, alignment: .trailing)
                }
            }
            .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))

            pickerRow(icon: "repeat", title: "重复") {
                Picker("", selection: $repeatOption) {
                    ForEach(ReminderRepeatOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 250, alignment: .trailing)
            }
            .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .frame(width: 440)
        .environment(\.locale, effectiveLanguage.locale)
        .onAppear(perform: loadReminder)
        .onChange(of: selectedDate) { _, _ in updateReminder() }
        .onChange(of: selectedTime) { _, _ in updateReminder() }
        .onChange(of: repeatOption) { _, _ in updateReminder() }
    }

    private var header: some View {
        HStack {
            Text("通知提醒")
                .font(.headline)

            Spacer()

            Button(role: .destructive) {
                reminder = nil
                onReminderChange(nil)
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("删除提醒")
            .disabled(reminder == nil)
        }
    }

    private func pickerRow<PickerContent: View>(
        icon: String,
        title: LocalizedStringKey,
        @ViewBuilder picker: () -> PickerContent
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(title)
                .font(.headline)

            Spacer(minLength: 16)

            picker()
        }
        .padding(12)
    }

    private func loadReminder() {
        guard let reminder else {
            selectedDate = Date()
            selectedTime = Date()
            repeatOption = .never
            updateReminder()
            return
        }

        if let fireTimestamp = reminder.fireTimestamp {
            selectedDate = fireTimestamp
            selectedTime = fireTimestamp
        } else {
            selectedDate = Date()
            selectedTime = Self.date(fromFireTime: reminder.fireTime) ?? Date()
        }

        repeatOption = ReminderRepeatOption(reminder: reminder)
    }

    private func updateReminder() {
        let fireTimestamp = selectedDate.combined(withTimeFrom: selectedTime)
        reminder = Reminder(
            type: repeatOption == .never ? "single" : "repeating",
            fireTime: repeatOption == .never ? nil : selectedTime.fireTimeString,
            fireTimestamp: fireTimestamp,
            repeatIntervalDays: repeatOption.repeatIntervalDays
        )
        onReminderChange(reminder)
    }

    private static func date(fromFireTime fireTime: String?) -> Date? {
        guard let fireTime else { return nil }
        let parts = fireTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0
        return Calendar.current.date(from: components)
    }
}

private enum ReminderRepeatOption: String, CaseIterable, Identifiable {
    case never
    case hourly
    case daily
    case every2Days
    case every3Days
    case weekdays
    case weekly
    case biweekly
    case monthly
    case every3Months
    case every6Months
    case yearly

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .never: "永不"
        case .hourly: "每小时"
        case .daily: "每天"
        case .every2Days: "每2天"
        case .every3Days: "每3天"
        case .weekdays: "工作日"
        case .weekly: "每周"
        case .biweekly: "每两周"
        case .monthly: "每月"
        case .every3Months: "每3个月"
        case .every6Months: "每6个月"
        case .yearly: "每年"
        }
    }

    var repeatIntervalDays: Int? {
        switch self {
        case .never:
            nil
        case .hourly:
            0
        case .daily:
            1
        case .every2Days:
            2
        case .every3Days:
            3
        case .weekdays:
            -1
        case .weekly:
            7
        case .biweekly:
            14
        case .monthly:
            30
        case .every3Months:
            90
        case .every6Months:
            180
        case .yearly:
            365
        }
    }

    init(reminder: Reminder) {
        guard reminder.type == "repeating" else {
            self = .never
            return
        }

        switch reminder.repeatIntervalDays {
        case 0: self = .hourly
        case 1: self = .daily
        case 2: self = .every2Days
        case 3: self = .every3Days
        case -1: self = .weekdays
        case 7: self = .weekly
        case 14: self = .biweekly
        case 30: self = .monthly
        case 90: self = .every3Months
        case 180: self = .every6Months
        case 365: self = .yearly
        default: self = .never
        }
    }
}

private extension Date {
    var fireTimeString: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    func combined(withTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: self)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = 0
        return calendar.date(from: dateComponents) ?? self
    }
}

#Preview {
    ReminderSettingsPopover(reminder: .constant(nil))
        .modelContainer(for: AppSettings.self, inMemory: true)
}
