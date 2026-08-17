import Foundation

enum OverviewCardTaskCount: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    static func resolve(_ storedValue: Int?) -> OverviewCardTaskCount {
        OverviewCardTaskCount(rawValue: storedValue ?? 1) ?? .one
    }
}

enum OverviewCardTaskCountSettingsStore {
    static let key = "overviewCardTaskCount"

    static func value(defaults: UserDefaults = .standard) -> OverviewCardTaskCount {
        OverviewCardTaskCount.resolve(defaults.object(forKey: key) as? Int)
    }

    static func set(
        _ value: OverviewCardTaskCount,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(value.rawValue, forKey: key)
    }
}

enum OverviewCardConfiguration {
    static func milestones(
        for project: Project,
        count: OverviewCardTaskCount
    ) -> [Milestone] {
        Array(project.unfinishedMilestones.prefix(count.rawValue))
    }

    static func cardHeight(for count: OverviewCardTaskCount) -> CGFloat {
        187 + CGFloat(count.rawValue - 1) * 48
    }
}
