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
    case more
    case about
    case display
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
    case weekSummary
    case conclusion
    case recentActivities
    case continuityTrend
    case weightTrend
    case volumeTrend
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
