import SwiftUI

struct IOSPersistentReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder?
    let onSubmit: (Reminder?) -> Void

    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var repeatOption: IOSReminderRepeatOption

    init(reminder: Reminder?, onSubmit: @escaping (Reminder?) -> Void) {
        self.reminder = reminder
        self.onSubmit = onSubmit
        let timestamp = reminder?.fireTimestamp ?? {
            let now = Date()
            return Calendar.current.date(
                bySettingHour: Calendar.current.component(.hour, from: now) + 1,
                minute: 0,
                second: 0,
                of: now
            ) ?? now
        }()
        _selectedDate = State(initialValue: timestamp)
        _selectedTime = State(initialValue: timestamp)
        _repeatOption = State(initialValue: IOSReminderRepeatOption(reminder: reminder))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                DatePicker("时间", selection: $selectedTime, displayedComponents: .hourAndMinute)
                Picker("重复", selection: $repeatOption) {
                    ForEach(IOSReminderRepeatOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            .navigationTitle("通知提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("删除", role: .destructive) {
                        onSubmit(nil)
                        dismiss()
                    }
                    .tint(.red)
                    .disabled(reminder == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSubmit(buildReminder())
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func buildReminder() -> Reminder {
        Reminder(
            type: repeatOption == .never ? "single" : "repeating",
            fireTime: repeatOption == .never ? nil : selectedTime.iosFireTimeString,
            fireTimestamp: selectedDate.iosCombined(withTimeFrom: selectedTime),
            repeatIntervalDays: repeatOption.repeatIntervalDays
        )
    }
}

struct IOSPersistentReminderSummary: View {
    let reminder: Reminder
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage
    var includesAlarmIcon = true
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 5) {
            if includesAlarmIcon {
                Image(systemName: "alarm.fill")
            }
            if let fireDate = reminder.displayFireDate {
                Text(AppDateFormatter.string(from: fireDate, pattern: dateFormatPattern))
            } else {
                Text("--")
            }
            if reminder.isRepeating {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .semibold))
                Text(reminder.repeatTitle(language: language))
            }
        }
        .font(font)
        .foregroundStyle(summaryColor)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var summaryColor: Color {
        reminder.displayFireDate.map { IOSPrototypeReminderStyle.color(for: $0) } ?? .gray
    }
}

private enum IOSReminderRepeatOption: String, CaseIterable, Identifiable {
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
        case .never: nil
        case .hourly: 0
        case .daily: 1
        case .every2Days: 2
        case .every3Days: 3
        case .weekdays: -1
        case .weekly: 7
        case .biweekly: 14
        case .monthly: 30
        case .every3Months: 90
        case .every6Months: 180
        case .yearly: 365
        }
    }

    init(reminder: Reminder?) {
        guard let reminder, reminder.type == "repeating" else {
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
    var iosFireTimeString: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    func iosCombined(withTimeFrom time: Date) -> Date {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: self)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = 0
        return calendar.date(from: dateComponents) ?? self
    }
}
