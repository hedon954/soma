import Foundation

enum SomaWidgetDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case fixedPlan
    case trainingRhythm
    case quickCapture

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .fixedPlan: "固定计划"
        case .trainingRhythm: "训练节奏"
        case .quickCapture: "快速记录"
        }
    }
}

enum SomaWidgetPrivacyLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case privateMode
    case overview
    case trainingDetail

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .privateMode: "私密"
        case .overview: "概览"
        case .trainingDetail: "训练详情"
        }
    }
}

struct SomaWidgetPreferences: Codable, Equatable, Sendable {
    var displayMode: SomaWidgetDisplayMode
    var privacyLevel: SomaWidgetPrivacyLevel
    var fixedProgramID: UUID?

    init(
        displayMode: SomaWidgetDisplayMode = .automatic,
        privacyLevel: SomaWidgetPrivacyLevel = .privateMode,
        fixedProgramID: UUID? = nil
    ) {
        self.displayMode = displayMode
        self.privacyLevel = privacyLevel
        self.fixedProgramID = fixedProgramID
    }
}

enum SomaWidgetSharedStore {
    static let suiteName = "group.top.hedon.soma"
    static let preferencesKey = "soma.widget.preferences.v1"
    static let snapshotKey = "soma.widget.snapshot.v1"

    static func loadPreferences(from defaults: UserDefaults? = sharedDefaults) -> SomaWidgetPreferences {
        guard let data = defaults?.data(forKey: preferencesKey),
              let value = try? JSONDecoder().decode(SomaWidgetPreferences.self, from: data)
        else {
            return SomaWidgetPreferences()
        }
        return value
    }

    static func savePreferences(
        _ preferences: SomaWidgetPreferences,
        to defaults: UserDefaults? = sharedDefaults
    ) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults?.set(data, forKey: preferencesKey)
    }

    static func loadSnapshot(from defaults: UserDefaults? = sharedDefaults) -> SomaWidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(SomaWidgetSnapshot.self, from: data)
    }

    static func saveSnapshot(
        _ snapshot: SomaWidgetSnapshot,
        to defaults: UserDefaults? = sharedDefaults
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func clearSnapshot(from defaults: UserDefaults? = sharedDefaults) {
        defaults?.removeObject(forKey: snapshotKey)
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
}

struct SomaWidgetSnapshot: Codable, Equatable, Sendable {
    struct Session: Codable, Equatable, Sendable {
        var id: UUID
        var completedSetCount: Int
        var totalSetCount: Int
        var planName: String?
    }

    struct Program: Codable, Equatable, Sendable {
        var id: UUID
        var name: String?
    }

    var schemaVersion: Int
    var dataSpaceRaw: String
    var generatedAt: Date
    var activeSession: Session?
    var fixedProgram: Program?
    var weekWorkoutCount: Int
    var daysSinceLastWorkout: Int?

    init(
        schemaVersion: Int = 1,
        dataSpaceRaw: String,
        generatedAt: Date = .now,
        activeSession: Session? = nil,
        fixedProgram: Program? = nil,
        weekWorkoutCount: Int = 0,
        daysSinceLastWorkout: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.dataSpaceRaw = dataSpaceRaw
        self.generatedAt = generatedAt
        self.activeSession = activeSession
        self.fixedProgram = fixedProgram
        self.weekWorkoutCount = weekWorkoutCount
        self.daysSinceLastWorkout = daysSinceLastWorkout
    }
}

struct SomaWidgetContent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case resume
        case fixedPlan
        case rhythm
        case firstTraining
        case quickCapture
        case unavailable
    }

    var kind: Kind
    var title: String
    var detail: String
    var route: URL
}

enum SomaWidgetContentResolver {
    static func resolve(
        snapshot: SomaWidgetSnapshot?,
        preferences: SomaWidgetPreferences,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SomaWidgetContent {
        guard let snapshot else {
            return unavailable()
        }

        if let session = snapshot.activeSession {
            let detail: String
            switch preferences.privacyLevel {
            case .privateMode:
                detail = "点按返回当前训练"
            case .overview:
                detail = "已完成 \(session.completedSetCount)/\(session.totalSetCount) 组"
            case .trainingDetail:
                let name = session.planName ?? "当前训练"
                detail = "\(name) · \(session.completedSetCount)/\(session.totalSetCount) 组"
            }
            return SomaWidgetContent(
                kind: .resume,
                title: "继续带练",
                detail: detail,
                route: workoutRoute(session.id)
            )
        }

        switch preferences.displayMode {
        case .quickCapture:
            return quickCapture()
        case .fixedPlan:
            if let program = snapshot.fixedProgram {
                return fixedPlan(program, privacy: preferences.privacyLevel)
            }
            return fallback(snapshot, preferences: preferences, now: now, calendar: calendar)
        case .trainingRhythm:
            return rhythm(snapshot, now: now, calendar: calendar)
        case .automatic:
            return fallback(snapshot, preferences: preferences, now: now, calendar: calendar)
        }
    }

    private static func fallback(
        _ snapshot: SomaWidgetSnapshot,
        preferences: SomaWidgetPreferences,
        now: Date,
        calendar: Calendar
    ) -> SomaWidgetContent {
        if let program = snapshot.fixedProgram {
            return fixedPlan(program, privacy: preferences.privacyLevel)
        }
        if snapshot.weekWorkoutCount > 0 || snapshot.daysSinceLastWorkout != nil {
            return rhythm(snapshot, now: now, calendar: calendar)
        }
        return SomaWidgetContent(
            kind: .firstTraining,
            title: "开始训练",
            detail: "记录第一条训练，或建立一个计划。",
            route: trainingRoute
        )
    }

    private static func fixedPlan(
        _ program: SomaWidgetSnapshot.Program,
        privacy: SomaWidgetPrivacyLevel
    ) -> SomaWidgetContent {
        SomaWidgetContent(
            kind: .fixedPlan,
            title: privacy == .trainingDetail
                ? (program.name ?? "固定计划")
                : "准备训练",
            detail: privacy == .trainingDetail
                ? "点按查看开始前确认"
                : "打开固定训练计划",
            route: trainingProgramRoute(program.id)
        )
    }

    private static func rhythm(
        _ snapshot: SomaWidgetSnapshot,
        now: Date,
        calendar: Calendar
    ) -> SomaWidgetContent {
        let detail: String = if snapshot.weekWorkoutCount > 0 {
            "本周已训练 \(snapshot.weekWorkoutCount) 次"
        } else if let days = snapshot.daysSinceLastWorkout {
            days == 0 ? "今天已经训练过" : "距上次训练 \(days) 天"
        } else {
            "打开训练，开始下一次记录"
        }
        return SomaWidgetContent(
            kind: .rhythm,
            title: "训练节奏",
            detail: detail,
            route: trainingRoute
        )
    }

    private static func quickCapture() -> SomaWidgetContent {
        SomaWidgetContent(
            kind: .quickCapture,
            title: "快速记录",
            detail: "文字、拍照或添加媒体。",
            route: textCaptureRoute
        )
    }

    private static func unavailable() -> SomaWidgetContent {
        SomaWidgetContent(
            kind: .unavailable,
            title: "打开 Soma",
            detail: "更新训练状态后再继续。",
            route: trainingRoute
        )
    }

    static let trainingRoute = URL(string: "soma://training")!
    static let textCaptureRoute = URL(string: "soma://capture/text")!

    static func workoutRoute(_ sessionID: UUID) -> URL {
        URL(string: "soma://workout/session/\(sessionID.uuidString)")!
    }

    static func trainingProgramRoute(_ programID: UUID) -> URL {
        URL(string: "soma://training/program/\(programID.uuidString)")!
    }
}
