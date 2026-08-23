import Foundation
import SwiftData

enum TrainingProgramStatus: String, Codable, CaseIterable, Sendable {
    case active
    case archived
}

enum WorkoutSessionStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case paused
    case completed
    case abandoned
}

enum ExercisePerformanceStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case active
    case completed
    case skipped
}

enum WorkoutSetKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case working
    case drop
    case failure
    case custom
}

enum WorkoutSetStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress
    case partial
    case completed
    case skipped
    case failed
}

/// 动作的左右方式。`.none` 表示全身、不区分侧别。
enum ExerciseLaterality: String, Codable, CaseIterable, Sendable {
    case none
    case both
    case left
    case right

    var displayName: String {
        switch self {
        case .none: "全身"
        case .both: "左右分开"
        case .left: "只左边"
        case .right: "只右边"
        }
    }
}

enum WorkoutTargetKind: String, Codable, CaseIterable, Sendable {
    case repetitions
    case duration

    var displayName: String {
        switch self {
        case .repetitions: "按次数"
        case .duration: "按时长"
        }
    }
}

enum WorkoutEffortSide: String, Codable, CaseIterable, Sendable {
    case none
    case left
    case right
}

enum WorkoutEffortStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress
    case completed
    case skipped
    case failed
}

enum WorkoutRecordingEvidenceKind: String, Codable, CaseIterable, Sendable {
    case complete
    case partial
}

enum WorkoutRecordingPauseCode: String, Codable, CaseIterable, Sendable {
    case permissionDenied
    case cameraUnavailable
    case configurationFailed
    case activationTimedOut
    case connectionUnavailable
    case insufficientStorage
    case interrupted
    case recordingFailed
    case unknown
}

enum AutoRecordingPolicy: String, Codable, CaseIterable, Sendable {
    case disabled
    /// 自动录制每个动作的首个工作组；保留旧值以兼容已有训练记录。
    case enabled
    case everySet
    case paused
    case cancelled

    var usesAutomaticRecording: Bool {
        self == .enabled || self == .everySet
    }
}

enum GuidedWorkoutPhase: String, Codable, CaseIterable, Sendable {
    case ready
    case exerciseIntroduction
    case preSetCountdown
    case setInProgress
    case setConfirmation
    case resting
    case sessionReview
    case completed
}

struct TemplateExercisePrescription: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetWeightKG: Double?
    var targetRestSeconds: Int?
    var restBetweenSidesSeconds: Int?
    var firstSetIsWarmup: Bool
    var equipmentKind: String?
    var notes: String
    var laterality: ExerciseLaterality
    var plannedSets: [TemplateSetPrescriptionValue]

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        exerciseName: String,
        order: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKG: Double? = nil,
        targetRestSeconds: Int? = nil,
        restBetweenSidesSeconds: Int? = nil,
        firstSetIsWarmup: Bool = false,
        equipmentKind: String? = nil,
        notes: String = "",
        laterality: ExerciseLaterality = .none,
        plannedSets: [TemplateSetPrescriptionValue]? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKG = targetWeightKG
        self.targetRestSeconds = targetRestSeconds
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.firstSetIsWarmup = firstSetIsWarmup
        self.equipmentKind = equipmentKind
        self.notes = notes
        self.laterality = laterality
        let rawSets = plannedSets ?? Self.expandLegacySets(
            targetSets: targetSets,
            targetReps: targetReps,
            targetWeightKG: targetWeightKG,
            targetRestSeconds: targetRestSeconds,
            firstSetIsWarmup: firstSetIsWarmup
        )
        if self.targetRestSeconds == nil {
            self.targetRestSeconds = Self.consensus(
                Array(rawSets.dropLast()).map(\.restAfterSetSeconds)
            )
        }
        if self.restBetweenSidesSeconds == nil {
            self.restBetweenSidesSeconds = Self.consensus(
                rawSets.map(\.restBetweenSidesSeconds)
            )
        }
        self.plannedSets = rawSets.map { value in
            var copy = value
            copy.restBetweenSidesSeconds = nil
            copy.restAfterSetSeconds = nil
            return copy
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, exerciseName, order
        case targetSets, targetReps, targetWeightKG, targetRestSeconds
        case restBetweenSidesSeconds
        case firstSetIsWarmup, equipmentKind, notes, laterality, plannedSets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        exerciseID = try values.decode(UUID.self, forKey: .exerciseID)
        exerciseName = try values.decode(String.self, forKey: .exerciseName)
        order = try values.decode(Int.self, forKey: .order)
        targetSets = try values.decodeIfPresent(Int.self, forKey: .targetSets)
        targetReps = try values.decodeIfPresent(Int.self, forKey: .targetReps)
        targetWeightKG = try values.decodeIfPresent(Double.self, forKey: .targetWeightKG)
        targetRestSeconds = try values.decodeIfPresent(Int.self, forKey: .targetRestSeconds)
        restBetweenSidesSeconds = try values.decodeIfPresent(
            Int.self,
            forKey: .restBetweenSidesSeconds
        )
        firstSetIsWarmup = try values.decodeIfPresent(
            Bool.self,
            forKey: .firstSetIsWarmup
        ) ?? false
        equipmentKind = try values.decodeIfPresent(String.self, forKey: .equipmentKind)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        laterality = try values.decodeIfPresent(
            ExerciseLaterality.self,
            forKey: .laterality
        ) ?? .none
        let rawSets = try values.decodeIfPresent(
            [TemplateSetPrescriptionValue].self,
            forKey: .plannedSets
        ) ?? Self.expandLegacySets(
            targetSets: targetSets,
            targetReps: targetReps,
            targetWeightKG: targetWeightKG,
            targetRestSeconds: targetRestSeconds,
            firstSetIsWarmup: firstSetIsWarmup
        )
        if targetRestSeconds == nil {
            targetRestSeconds = Self.consensus(
                Array(rawSets.dropLast()).map(\.restAfterSetSeconds)
            )
        }
        if restBetweenSidesSeconds == nil {
            restBetweenSidesSeconds = Self.consensus(
                rawSets.map(\.restBetweenSidesSeconds)
            )
        }
        plannedSets = rawSets.map { value in
            var copy = value
            copy.restBetweenSidesSeconds = nil
            copy.restAfterSetSeconds = nil
            return copy
        }
    }

    private static func consensus(_ values: [Int?]) -> Int? {
        guard !values.isEmpty,
              let first = values[0],
              values.dropFirst().allSatisfy({ $0 == first })
        else {
            return nil
        }
        return first
    }

    static func expandLegacySets(
        targetSets: Int?,
        targetReps: Int?,
        targetWeightKG: Double?,
        targetRestSeconds: Int?,
        firstSetIsWarmup: Bool
    ) -> [TemplateSetPrescriptionValue] {
        guard let targetSets, targetSets > 0 else { return [] }
        return (0 ..< targetSets).map { index in
            TemplateSetPrescriptionValue(
                order: index + 1,
                kind: firstSetIsWarmup && index == 0 ? .warmup : .working,
                targetKind: .repetitions,
                targetReps: targetReps,
                targetWeightKG: targetWeightKG,
                restAfterSetSeconds: index + 1 < targetSets
                    ? targetRestSeconds
                    : nil
            )
        }
    }
}

/// 计划快照中的独立组值；持久模型使用 `TemplateSetPrescription`。
struct TemplateSetPrescriptionValue: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var order: Int
    var kind: WorkoutSetKind
    var targetKind: WorkoutTargetKind
    var targetReps: Int?
    var targetDurationSeconds: Int?
    var targetWeightKG: Double?
    var leftWeightKG: Double?
    var rightWeightKG: Double?
    var restBetweenSidesSeconds: Int?
    var restAfterSetSeconds: Int?
    var notes: String

    init(
        id: UUID = UUID(),
        order: Int,
        kind: WorkoutSetKind = .working,
        targetKind: WorkoutTargetKind = .repetitions,
        targetReps: Int? = nil,
        targetDurationSeconds: Int? = nil,
        targetWeightKG: Double? = nil,
        leftWeightKG: Double? = nil,
        rightWeightKG: Double? = nil,
        restBetweenSidesSeconds: Int? = nil,
        restAfterSetSeconds: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.targetKind = targetKind
        self.targetReps = targetReps
        self.targetDurationSeconds = targetDurationSeconds
        self.targetWeightKG = targetWeightKG
        self.leftWeightKG = leftWeightKG
        self.rightWeightKG = rightWeightKG
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.restAfterSetSeconds = restAfterSetSeconds
        self.notes = notes
    }

    func weight(for side: WorkoutEffortSide) -> Double? {
        switch side {
        case .none:
            targetWeightKG
        case .left:
            leftWeightKG ?? targetWeightKG
        case .right:
            rightWeightKG ?? targetWeightKG
        }
    }
}

enum TrainingPlanCoding {
    static func encode(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Model
final class TrainingProgram: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var name: String
    @Attribute(originalName: "goal") var overview: String
    var statusRaw: String
    @Attribute(originalName: "currentTemplateVersionID") var prescriptionGroupID: UUID?
    var scheduleHint: String = ""
    var createdAt: Date
    var updatedAt: Date
    @Relationship(
        deleteRule: .cascade,
        inverse: \TemplateExercise.program
    ) var templateExercises: [TemplateExercise] = []

    init(
        id: UUID = UUID(),
        name: String,
        goal: String = "",
        overview: String? = nil,
        status: TrainingProgramStatus = .active,
        prescriptionGroupID: UUID? = nil,
        scheduleHint: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview ?? goal
        statusRaw = status.rawValue
        self.prescriptionGroupID = prescriptionGroupID ?? id
        self.scheduleHint = scheduleHint
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// V4/UI compatibility. New code should use `overview`.
    var goal: String {
        get { overview }
        set { overview = newValue }
    }

    var status: TrainingProgramStatus {
        get { TrainingProgramStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}

@Model
final class TemplateExercise: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    @Attribute(originalName: "templateVersionID") var prescriptionGroupID: UUID
    var exerciseID: UUID
    @Relationship(deleteRule: .nullify) var program: TrainingProgram?
    @Relationship(deleteRule: .nullify) var exerciseDefinition: ExerciseDefinition?
    var order: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetWeightKG: Double?
    var targetRestSeconds: Int?
    var restBetweenSidesSeconds: Int?
    var firstSetIsWarmup: Bool
    var equipmentKind: String?
    var notes: String
    var lateralityRaw: String = ExerciseLaterality.none.rawValue
    @Relationship(
        deleteRule: .cascade,
        inverse: \TemplateSetPrescription.templateExercise
    ) var setPrescriptions: [TemplateSetPrescription] = []

    init(
        id: UUID = UUID(),
        prescriptionGroupID: UUID,
        exerciseID: UUID,
        order: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKG: Double? = nil,
        targetRestSeconds: Int? = nil,
        restBetweenSidesSeconds: Int? = nil,
        firstSetIsWarmup: Bool = false,
        equipmentKind: String? = nil,
        notes: String = "",
        laterality: ExerciseLaterality = .none
    ) {
        self.id = id
        self.prescriptionGroupID = prescriptionGroupID
        self.exerciseID = exerciseID
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKG = targetWeightKG
        self.targetRestSeconds = targetRestSeconds
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.firstSetIsWarmup = firstSetIsWarmup
        self.equipmentKind = equipmentKind
        self.notes = notes
        lateralityRaw = laterality.rawValue
    }

    var laterality: ExerciseLaterality {
        get { ExerciseLaterality(rawValue: lateralityRaw) ?? .none }
        set { lateralityRaw = newValue.rawValue }
    }
}

@Model
final class TemplateSetPrescription: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var templateExerciseID: UUID
    @Relationship(deleteRule: .nullify) var templateExercise: TemplateExercise?
    var order: Int
    var kindRaw: String
    var targetKindRaw: String
    var targetReps: Int?
    var targetDurationSeconds: Int?
    var targetWeightKG: Double?
    var leftWeightKG: Double?
    var rightWeightKG: Double?
    var restBetweenSidesSeconds: Int?
    var restAfterSetSeconds: Int?
    var notes: String

    init(
        id: UUID = UUID(),
        templateExerciseID: UUID,
        order: Int,
        kind: WorkoutSetKind = .working,
        targetKind: WorkoutTargetKind = .repetitions,
        targetReps: Int? = nil,
        targetDurationSeconds: Int? = nil,
        targetWeightKG: Double? = nil,
        leftWeightKG: Double? = nil,
        rightWeightKG: Double? = nil,
        restBetweenSidesSeconds: Int? = nil,
        restAfterSetSeconds: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.templateExerciseID = templateExerciseID
        self.order = order
        kindRaw = kind.rawValue
        targetKindRaw = targetKind.rawValue
        self.targetReps = targetReps
        self.targetDurationSeconds = targetDurationSeconds
        self.targetWeightKG = targetWeightKG
        self.leftWeightKG = leftWeightKG
        self.rightWeightKG = rightWeightKG
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.restAfterSetSeconds = restAfterSetSeconds
        self.notes = notes
    }

    convenience init(
        templateExerciseID: UUID,
        value: TemplateSetPrescriptionValue
    ) {
        self.init(
            id: value.id,
            templateExerciseID: templateExerciseID,
            order: value.order,
            kind: value.kind,
            targetKind: value.targetKind,
            targetReps: value.targetReps,
            targetDurationSeconds: value.targetDurationSeconds,
            targetWeightKG: value.targetWeightKG,
            leftWeightKG: value.leftWeightKG,
            rightWeightKG: value.rightWeightKG,
            restBetweenSidesSeconds: value.restBetweenSidesSeconds,
            restAfterSetSeconds: value.restAfterSetSeconds,
            notes: value.notes
        )
    }

    var kind: WorkoutSetKind {
        get { WorkoutSetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var targetKind: WorkoutTargetKind {
        get { WorkoutTargetKind(rawValue: targetKindRaw) ?? .repetitions }
        set { targetKindRaw = newValue.rawValue }
    }

    var value: TemplateSetPrescriptionValue {
        TemplateSetPrescriptionValue(
            id: id,
            order: order,
            kind: kind,
            targetKind: targetKind,
            targetReps: targetReps,
            targetDurationSeconds: targetDurationSeconds,
            targetWeightKG: targetWeightKG,
            leftWeightKG: leftWeightKG,
            rightWeightKG: rightWeightKG,
            restBetweenSidesSeconds: restBetweenSidesSeconds,
            restAfterSetSeconds: restAfterSetSeconds,
            notes: notes
        )
    }
}

@Model
final class WorkoutSession: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var startedAt: Date
    var endedAt: Date?
    var gymID: UUID?
    var programID: UUID?
    var programNameSnapshot: String?
    var prescriptionSnapshotData: Data
    var statusRaw: String
    var guidedPhaseRaw: String
    var currentPerformanceID: UUID?
    var currentSetID: UUID?
    var currentEffortID: UUID?
    var phaseStartedAt: Date?
    var phaseDeadlineAt: Date?
    var transitionRevision: Int = 0
    var restStartedAt: Date?
    var restTargetEndAt: Date?
    var autoRecordingPolicyRaw: String
    var queuedRecordingEffortID: UUID?
    var automaticRecordingPaused: Bool = false
    var automaticRecordingPauseCodeRaw: String?
    var automaticRecordingPauseReason: String?
    var sourceTurnID: UUID?
    var sourceJobID: UUID?
    @Relationship(
        deleteRule: .cascade,
        inverse: \ExercisePerformance.session
    ) var performances: [ExercisePerformance] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        gymID: UUID? = nil,
        programID: UUID? = nil,
        programNameSnapshot: String? = nil,
        prescriptionSnapshot: [TemplateExercisePrescription] = [],
        status: WorkoutSessionStatus = .draft,
        guidedPhase: GuidedWorkoutPhase = .ready,
        currentPerformanceID: UUID? = nil,
        currentSetID: UUID? = nil,
        currentEffortID: UUID? = nil,
        phaseStartedAt: Date? = nil,
        phaseDeadlineAt: Date? = nil,
        transitionRevision: Int = 0,
        restStartedAt: Date? = nil,
        restTargetEndAt: Date? = nil,
        autoRecordingPolicy: AutoRecordingPolicy = .disabled,
        queuedRecordingEffortID: UUID? = nil,
        automaticRecordingPaused: Bool = false,
        automaticRecordingPauseCode: WorkoutRecordingPauseCode? = nil,
        automaticRecordingPauseReason: String? = nil,
        sourceTurnID: UUID? = nil,
        sourceJobID: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.gymID = gymID
        self.programID = programID
        self.programNameSnapshot = programNameSnapshot
        prescriptionSnapshotData = TrainingPlanCoding.encode(prescriptionSnapshot)
        statusRaw = status.rawValue
        guidedPhaseRaw = guidedPhase.rawValue
        self.currentPerformanceID = currentPerformanceID
        self.currentSetID = currentSetID
        self.currentEffortID = currentEffortID
        self.phaseStartedAt = phaseStartedAt
        self.phaseDeadlineAt = phaseDeadlineAt
        self.transitionRevision = transitionRevision
        self.restStartedAt = restStartedAt
        self.restTargetEndAt = restTargetEndAt
        autoRecordingPolicyRaw = autoRecordingPolicy.rawValue
        self.queuedRecordingEffortID = queuedRecordingEffortID
        self.automaticRecordingPaused = automaticRecordingPaused
        automaticRecordingPauseCodeRaw = automaticRecordingPauseCode?.rawValue
        self.automaticRecordingPauseReason = automaticRecordingPauseReason
        self.sourceTurnID = sourceTurnID
        self.sourceJobID = sourceJobID
    }

    var prescriptionSnapshot: [TemplateExercisePrescription] {
        TrainingPlanCoding.decode(
            [TemplateExercisePrescription].self,
            from: prescriptionSnapshotData
        ) ?? []
    }

    var status: WorkoutSessionStatus {
        get { WorkoutSessionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var guidedPhase: GuidedWorkoutPhase {
        get { GuidedWorkoutPhase(rawValue: guidedPhaseRaw) ?? .ready }
        set { guidedPhaseRaw = newValue.rawValue }
    }

    var autoRecordingPolicy: AutoRecordingPolicy {
        get {
            AutoRecordingPolicy(rawValue: autoRecordingPolicyRaw) ?? .disabled
        }
        set { autoRecordingPolicyRaw = newValue.rawValue }
    }

    var automaticRecordingPauseCode: WorkoutRecordingPauseCode? {
        get {
            automaticRecordingPauseCodeRaw.flatMap(
                WorkoutRecordingPauseCode.init(rawValue:)
            )
        }
        set { automaticRecordingPauseCodeRaw = newValue?.rawValue }
    }
}

@Model
final class ExercisePerformance: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var sessionID: UUID
    @Relationship(deleteRule: .nullify) var session: WorkoutSession?
    var exerciseID: UUID
    @Relationship(deleteRule: .nullify) var exerciseDefinition: ExerciseDefinition?
    var exerciseName: String
    var order: Int
    var prescriptionSnapshotData: Data
    var statusRaw: String
    var notes: String
    var activeVideoPath: String?
    var activeVideoKindRaw: String?
    var workoutProjectionSuppressed: Bool = false
    @Relationship(
        deleteRule: .nullify,
        inverse: \WorkoutEntry.sourcePerformance
    ) var projectedWorkout: WorkoutEntry?
    @Relationship(
        deleteRule: .cascade,
        inverse: \WorkoutSet.performance
    ) var workoutSets: [WorkoutSet] = []

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: UUID,
        exerciseName: String,
        order: Int,
        prescriptionSnapshot: TemplateExercisePrescription,
        status: ExercisePerformanceStatus = .pending,
        notes: String = "",
        activeVideoPath: String? = nil,
        activeVideoKind: WorkoutRecordingEvidenceKind? = nil,
        workoutProjectionSuppressed: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        prescriptionSnapshotData = TrainingPlanCoding.encode(prescriptionSnapshot)
        statusRaw = status.rawValue
        self.notes = notes
        self.activeVideoPath = activeVideoPath
        activeVideoKindRaw = activeVideoKind?.rawValue
        self.workoutProjectionSuppressed = workoutProjectionSuppressed
    }

    var prescriptionSnapshot: TemplateExercisePrescription? {
        TrainingPlanCoding.decode(
            TemplateExercisePrescription.self,
            from: prescriptionSnapshotData
        )
    }

    var status: ExercisePerformanceStatus {
        get {
            ExercisePerformanceStatus(rawValue: statusRaw) ?? .pending
        }
        set { statusRaw = newValue.rawValue }
    }

    var activeVideoKind: WorkoutRecordingEvidenceKind? {
        get {
            guard activeVideoPath != nil else { return nil }
            return activeVideoKindRaw.flatMap(
                WorkoutRecordingEvidenceKind.init(rawValue:)
            ) ?? .complete
        }
        set { activeVideoKindRaw = newValue?.rawValue }
    }
}

@Model
final class WorkoutSet: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var performanceID: UUID
    @Relationship(deleteRule: .nullify) var performance: ExercisePerformance?
    var order: Int
    var kindRaw: String
    var laterality: String?
    var plannedReps: Int?
    var plannedTargetKindRaw: String = WorkoutTargetKind.repetitions.rawValue
    var plannedDurationSeconds: Int?
    var plannedWeightKG: Double?
    var plannedRestSeconds: Int?
    var restBetweenSidesSeconds: Int?
    var actualReps: Int?
    var actualDurationSeconds: Int?
    var actualWeightKG: Double?
    var actualRestSeconds: Int?
    var statusRaw: String
    var startedAt: Date?
    var completedAt: Date?
    var recordedVideoPath: String?
    var recordedVideoKindRaw: String?
    @Relationship(
        deleteRule: .cascade,
        inverse: \WorkoutEffort.workoutSet
    ) var efforts: [WorkoutEffort] = []

    init(
        id: UUID = UUID(),
        performanceID: UUID,
        order: Int,
        kind: WorkoutSetKind = .working,
        laterality: String? = nil,
        plannedTargetKind: WorkoutTargetKind = .repetitions,
        plannedReps: Int? = nil,
        plannedDurationSeconds: Int? = nil,
        plannedWeightKG: Double? = nil,
        plannedRestSeconds: Int? = nil,
        restBetweenSidesSeconds: Int? = nil,
        actualReps: Int? = nil,
        actualDurationSeconds: Int? = nil,
        actualWeightKG: Double? = nil,
        actualRestSeconds: Int? = nil,
        status: WorkoutSetStatus = .pending,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        recordedVideoPath: String? = nil,
        recordedVideoKind: WorkoutRecordingEvidenceKind? = nil
    ) {
        self.id = id
        self.performanceID = performanceID
        self.order = order
        kindRaw = kind.rawValue
        self.laterality = laterality
        plannedTargetKindRaw = plannedTargetKind.rawValue
        self.plannedReps = plannedReps
        self.plannedDurationSeconds = plannedDurationSeconds
        self.plannedWeightKG = plannedWeightKG
        self.plannedRestSeconds = plannedRestSeconds
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.actualReps = actualReps
        self.actualDurationSeconds = actualDurationSeconds
        self.actualWeightKG = actualWeightKG
        self.actualRestSeconds = actualRestSeconds
        statusRaw = status.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.recordedVideoPath = recordedVideoPath
        recordedVideoKindRaw = recordedVideoKind?.rawValue
    }

    var kind: WorkoutSetKind {
        get { WorkoutSetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var status: WorkoutSetStatus {
        get { WorkoutSetStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var exerciseLaterality: ExerciseLaterality {
        get { laterality.flatMap(ExerciseLaterality.init(rawValue:)) ?? .none }
        set { laterality = newValue.rawValue }
    }

    var plannedTargetKind: WorkoutTargetKind {
        get {
            WorkoutTargetKind(rawValue: plannedTargetKindRaw) ?? .repetitions
        }
        set { plannedTargetKindRaw = newValue.rawValue }
    }

    var completedVolume: Double? {
        guard status == .completed,
              let actualReps,
              let actualWeightKG,
              actualReps > 0,
              actualWeightKG > 0
        else {
            return nil
        }
        return Double(actualReps) * actualWeightKG
    }

    var recordedVideoKind: WorkoutRecordingEvidenceKind? {
        get {
            guard recordedVideoPath != nil else { return nil }
            return recordedVideoKindRaw.flatMap(
                WorkoutRecordingEvidenceKind.init(rawValue:)
            ) ?? .complete
        }
        set { recordedVideoKindRaw = newValue?.rawValue }
    }
}

@Model
final class WorkoutEffort: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var workoutSetID: UUID
    @Relationship(deleteRule: .nullify) var workoutSet: WorkoutSet?
    var order: Int
    var sideRaw: String
    var targetKindRaw: String
    var plannedReps: Int?
    var plannedDurationSeconds: Int?
    var plannedWeightKG: Double?
    var actualReps: Int?
    var actualDurationSeconds: Int?
    var actualWeightKG: Double?
    var actualRestSeconds: Int?
    var statusRaw: String
    var startedAt: Date?
    var completedAt: Date?
    var recordedVideoPath: String?
    var recordedVideoKindRaw: String?

    init(
        id: UUID = UUID(),
        workoutSetID: UUID,
        order: Int,
        side: WorkoutEffortSide = .none,
        targetKind: WorkoutTargetKind = .repetitions,
        plannedReps: Int? = nil,
        plannedDurationSeconds: Int? = nil,
        plannedWeightKG: Double? = nil,
        actualReps: Int? = nil,
        actualDurationSeconds: Int? = nil,
        actualWeightKG: Double? = nil,
        actualRestSeconds: Int? = nil,
        status: WorkoutEffortStatus = .pending,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        recordedVideoPath: String? = nil,
        recordedVideoKind: WorkoutRecordingEvidenceKind? = nil
    ) {
        self.id = id
        self.workoutSetID = workoutSetID
        self.order = order
        sideRaw = side.rawValue
        targetKindRaw = targetKind.rawValue
        self.plannedReps = plannedReps
        self.plannedDurationSeconds = plannedDurationSeconds
        self.plannedWeightKG = plannedWeightKG
        self.actualReps = actualReps
        self.actualDurationSeconds = actualDurationSeconds
        self.actualWeightKG = actualWeightKG
        self.actualRestSeconds = actualRestSeconds
        statusRaw = status.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.recordedVideoPath = recordedVideoPath
        recordedVideoKindRaw = recordedVideoKind?.rawValue
    }

    var side: WorkoutEffortSide {
        get { WorkoutEffortSide(rawValue: sideRaw) ?? .none }
        set { sideRaw = newValue.rawValue }
    }

    var targetKind: WorkoutTargetKind {
        get { WorkoutTargetKind(rawValue: targetKindRaw) ?? .repetitions }
        set { targetKindRaw = newValue.rawValue }
    }

    var status: WorkoutEffortStatus {
        get { WorkoutEffortStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var recordedVideoKind: WorkoutRecordingEvidenceKind? {
        get {
            guard recordedVideoPath != nil else { return nil }
            return recordedVideoKindRaw.flatMap(
                WorkoutRecordingEvidenceKind.init(rawValue:)
            ) ?? .complete
        }
        set { recordedVideoKindRaw = newValue?.rawValue }
    }

    var completedVolume: Double? {
        guard status == .completed,
              let actualReps,
              let actualWeightKG,
              actualReps > 0,
              actualWeightKG > 0
        else {
            return nil
        }
        return Double(actualReps) * actualWeightKG
    }
}

@Model
final class RecommendationSnapshot: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var targetKind: String
    var targetID: UUID
    var inputFingerprint: String
    var advice: String
    var createdAt: Date
    var sourceJobID: UUID?

    init(
        id: UUID = UUID(),
        targetKind: String,
        targetID: UUID,
        inputFingerprint: String,
        advice: String,
        createdAt: Date = .now,
        sourceJobID: UUID? = nil
    ) {
        self.id = id
        self.targetKind = targetKind
        self.targetID = targetID
        self.inputFingerprint = inputFingerprint
        self.advice = advice
        self.createdAt = createdAt
        self.sourceJobID = sourceJobID
    }
}

@Model
final class PerformanceAnalysis: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var performanceID: UUID
    var sourceMediaPath: String
    var inputFingerprint: String
    var evidence: String
    var limitations: String
    var feedback: String
    var createdAt: Date
    var sourceJobID: UUID?

    init(
        id: UUID = UUID(),
        performanceID: UUID,
        sourceMediaPath: String,
        inputFingerprint: String,
        evidence: String,
        limitations: String,
        feedback: String,
        createdAt: Date = .now,
        sourceJobID: UUID? = nil
    ) {
        self.id = id
        self.performanceID = performanceID
        self.sourceMediaPath = sourceMediaPath
        self.inputFingerprint = inputFingerprint
        self.evidence = evidence
        self.limitations = limitations
        self.feedback = feedback
        self.createdAt = createdAt
        self.sourceJobID = sourceJobID
    }
}
