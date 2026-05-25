import Foundation

extension Reminder {
    var isRepeating: Bool {
        type == "repeating"
    }

    var displayFireDate: Date? {
        fireTimestamp ?? nextRepeatingFireDate(relativeTo: Date(), calendar: .current)
    }

    func displaySummary(dateFormatPattern: String?, language: EffectiveAppLanguage) -> String {
        let time = displayFireDate.map {
            AppDateFormatter.string(from: $0, pattern: dateFormatPattern)
        } ?? "--"
        guard isRepeating else { return time }
        return "\(time) \(repeatTitle(language: language))"
    }

    func isOverdue(at now: Date) -> Bool {
        guard let date = displayFireDate else { return false }
        return date < now
    }

    func isTodayPending(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let date = displayFireDate else { return false }
        return calendar.isDate(date, inSameDayAs: now) && date >= now
    }

    func repeatTitle(language: EffectiveAppLanguage) -> String {
        guard isRepeating else { return "" }
        let key: String
        switch repeatIntervalDays {
        case 0: key = "每小时"
        case 1: key = "每天"
        case 2: key = "每2天"
        case 3: key = "每3天"
        case -1: key = "工作日"
        case 7: key = "每周"
        case 14: key = "每两周"
        case 30: key = "每月"
        case 90: key = "每3个月"
        case 180: key = "每6个月"
        case 365: key = "每年"
        default: key = "循环"
        }
        return AppLocalization.string(key, language: language)
    }

    func nextFutureFireDate(after firedDate: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard isRepeating else { return nil }
        var candidate = firedDate
        for _ in 0..<10000 {
            guard let next = nextCycle(after: candidate, calendar: calendar) else { return nil }
            if next > now { return next }
            candidate = next
        }
        return nil
    }

    var postponedByOneCycle: Date? {
        guard isRepeating, let baseDate = displayFireDate else { return nil }
        return nextCycle(after: baseDate, calendar: .current)
    }

    private func nextRepeatingFireDate(relativeTo now: Date, calendar: Calendar) -> Date? {
        guard isRepeating, let fireTime else { return fireTimestamp }
        let parts = fireTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return fireTimestamp }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0

        guard let today = calendar.date(from: components) else { return fireTimestamp }
        return today >= now ? today : nextCycle(after: today, calendar: calendar)
    }

    private func nextCycle(after date: Date, calendar: Calendar) -> Date? {
        switch repeatIntervalDays {
        case 0:
            return calendar.date(byAdding: .hour, value: 1, to: date)
        case -1:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date)
            while let current = candidate {
                let weekday = calendar.component(.weekday, from: current)
                if weekday != 1 && weekday != 7 { return current }
                candidate = calendar.date(byAdding: .day, value: 1, to: current)
            }
            return nil
        case 30:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case 90:
            return calendar.date(byAdding: .month, value: 3, to: date)
        case 180:
            return calendar.date(byAdding: .month, value: 6, to: date)
        case 365:
            return calendar.date(byAdding: .year, value: 1, to: date)
        default:
            return calendar.date(byAdding: .day, value: repeatIntervalDays ?? 1, to: date)
        }
    }
}
