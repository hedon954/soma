import Foundation

enum TrainingProgramDetailAction: String, CaseIterable, Identifiable, Sendable {
    case editPlan
    case startTraining

    var id: String {
        rawValue
    }
}

enum SettingsHomeSection: String, CaseIterable, Identifiable, Sendable {
    case profileAndTraining
    case service
    case utilities
    case display
    case about
    case feedback

    var id: String {
        rawValue
    }
}

enum TrainingHomeSection: String, CaseIterable, Identifiable, Sendable {
    case resume
    case programs
    case recent
    case archived

    var id: String {
        rawValue
    }

    static func visible(
        hasResumableSession: Bool,
        hasRecentSessions: Bool,
        hasArchivedPrograms: Bool
    ) -> [TrainingHomeSection] {
        allCases.filter { section in
            switch section {
            case .resume: hasResumableSession
            case .programs: true
            case .recent: hasRecentSessions
            case .archived: hasArchivedPrograms
            }
        }
    }
}

enum ProgressHomeSection: String, CaseIterable, Identifiable, Sendable {
    case trainingOverview
    case conclusion
    case recentActivities
    case weightTrend
    case allData
    case currentGym
    case personalResources

    var id: String {
        rawValue
    }

    static func visible(
        hasRecentActivities: Bool,
        hasWeightTrend: Bool
    ) -> [ProgressHomeSection] {
        allCases.filter { section in
            switch section {
            case .recentActivities: hasRecentActivities
            case .weightTrend: hasWeightTrend
            default: true
            }
        }
    }
}

enum ProgressTrainingOverviewTab: String, CaseIterable, Identifiable, Sendable {
    case recentWeek
    case continuity
    case volume

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recentWeek: "近 7 天"
        case .continuity: "连续性"
        case .volume: "容量"
        }
    }
}
