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
    case completed
    case skipped
    case failed
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
    var firstSetIsWarmup: Bool
    var equipmentKind: String?
    var notes: String

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        exerciseName: String,
        order: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKG: Double? = nil,
        targetRestSeconds: Int? = nil,
        firstSetIsWarmup: Bool = false,
        equipmentKind: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKG = targetWeightKG
        self.targetRestSeconds = targetRestSeconds
        self.firstSetIsWarmup = firstSetIsWarmup
        self.equipmentKind = equipmentKind
        self.notes = notes
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
final class TrainingProgram {
    var id: UUID
    var name: String
    var goal: String
    var statusRaw: String
    var currentTemplateVersionID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        goal: String = "",
        status: TrainingProgramStatus = .active,
        currentTemplateVersionID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        statusRaw = status.rawValue
        self.currentTemplateVersionID = currentTemplateVersionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
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
final class WorkoutTemplateVersion {
    var id: UUID
    var programID: UUID
    var familyID: UUID
    var version: Int
    var name: String
    var scheduleHint: String
    var source: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        programID: UUID,
        familyID: UUID = UUID(),
        version: Int,
        name: String,
        scheduleHint: String = "",
        source: String = "user",
        createdAt: Date = .now
    ) {
        self.id = id
        self.programID = programID
        self.familyID = familyID
        self.version = version
        self.name = name
        self.scheduleHint = scheduleHint
        self.source = source
        self.createdAt = createdAt
    }
}

@Model
final class TemplateExercise {
    var id: UUID
    var templateVersionID: UUID
    var exerciseID: UUID
    var order: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetWeightKG: Double?
    var targetRestSeconds: Int?
    var firstSetIsWarmup: Bool
    var equipmentKind: String?
    var notes: String

    init(
        id: UUID = UUID(),
        templateVersionID: UUID,
        exerciseID: UUID,
        order: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKG: Double? = nil,
        targetRestSeconds: Int? = nil,
        firstSetIsWarmup: Bool = false,
        equipmentKind: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.templateVersionID = templateVersionID
        self.exerciseID = exerciseID
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKG = targetWeightKG
        self.targetRestSeconds = targetRestSeconds
        self.firstSetIsWarmup = firstSetIsWarmup
        self.equipmentKind = equipmentKind
        self.notes = notes
    }
}

@Model
final class WorkoutSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var gymID: UUID?
    var sourceTemplateFamilyID: UUID?
    var sourceTemplateVersion: Int?
    var prescriptionSnapshotData: Data
    var statusRaw: String
    var guidedPhaseRaw: String
    var currentPerformanceID: UUID?
    var currentSetID: UUID?
    var phaseStartedAt: Date?
    var restStartedAt: Date?
    var restTargetEndAt: Date?
    var autoRecordingPolicyRaw: String
    var sourceTurnID: UUID?
    var sourceJobID: UUID?

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        gymID: UUID? = nil,
        sourceTemplateFamilyID: UUID? = nil,
        sourceTemplateVersion: Int? = nil,
        prescriptionSnapshot: [TemplateExercisePrescription] = [],
        status: WorkoutSessionStatus = .draft,
        guidedPhase: GuidedWorkoutPhase = .ready,
        currentPerformanceID: UUID? = nil,
        currentSetID: UUID? = nil,
        phaseStartedAt: Date? = nil,
        restStartedAt: Date? = nil,
        restTargetEndAt: Date? = nil,
        autoRecordingPolicy: AutoRecordingPolicy = .disabled,
        sourceTurnID: UUID? = nil,
        sourceJobID: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.gymID = gymID
        self.sourceTemplateFamilyID = sourceTemplateFamilyID
        self.sourceTemplateVersion = sourceTemplateVersion
        prescriptionSnapshotData = TrainingPlanCoding.encode(prescriptionSnapshot)
        statusRaw = status.rawValue
        guidedPhaseRaw = guidedPhase.rawValue
        self.currentPerformanceID = currentPerformanceID
        self.currentSetID = currentSetID
        self.phaseStartedAt = phaseStartedAt
        self.restStartedAt = restStartedAt
        self.restTargetEndAt = restTargetEndAt
        autoRecordingPolicyRaw = autoRecordingPolicy.rawValue
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
}

@Model
final class ExercisePerformance {
    var id: UUID
    var sessionID: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var prescriptionSnapshotData: Data
    var statusRaw: String
    var notes: String
    var activeVideoPath: String?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: UUID,
        exerciseName: String,
        order: Int,
        prescriptionSnapshot: TemplateExercisePrescription,
        status: ExercisePerformanceStatus = .pending,
        notes: String = "",
        activeVideoPath: String? = nil
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
}

@Model
final class WorkoutSet {
    var id: UUID
    var performanceID: UUID
    var order: Int
    var kindRaw: String
    var laterality: String?
    var plannedReps: Int?
    var plannedWeightKG: Double?
    var plannedRestSeconds: Int?
    var actualReps: Int?
    var actualWeightKG: Double?
    var actualRestSeconds: Int?
    var statusRaw: String
    var startedAt: Date?
    var completedAt: Date?
    var recordedVideoPath: String?

    init(
        id: UUID = UUID(),
        performanceID: UUID,
        order: Int,
        kind: WorkoutSetKind = .working,
        laterality: String? = nil,
        plannedReps: Int? = nil,
        plannedWeightKG: Double? = nil,
        plannedRestSeconds: Int? = nil,
        actualReps: Int? = nil,
        actualWeightKG: Double? = nil,
        actualRestSeconds: Int? = nil,
        status: WorkoutSetStatus = .pending,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        recordedVideoPath: String? = nil
    ) {
        self.id = id
        self.performanceID = performanceID
        self.order = order
        kindRaw = kind.rawValue
        self.laterality = laterality
        self.plannedReps = plannedReps
        self.plannedWeightKG = plannedWeightKG
        self.plannedRestSeconds = plannedRestSeconds
        self.actualReps = actualReps
        self.actualWeightKG = actualWeightKG
        self.actualRestSeconds = actualRestSeconds
        statusRaw = status.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.recordedVideoPath = recordedVideoPath
    }

    var kind: WorkoutSetKind {
        get { WorkoutSetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var status: WorkoutSetStatus {
        get { WorkoutSetStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
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
final class RecommendationSnapshot {
    var id: UUID
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
final class PerformanceAnalysis {
    var id: UUID
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
