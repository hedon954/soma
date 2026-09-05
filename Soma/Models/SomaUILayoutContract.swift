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
