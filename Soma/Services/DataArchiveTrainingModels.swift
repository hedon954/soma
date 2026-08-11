import Foundation

struct TrainingProgramDTO: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var goal: String
    var statusRaw: String
    var currentTemplateVersionID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ model: TrainingProgram) {
        id = model.id
        name = model.name
        goal = model.goal
        statusRaw = model.statusRaw
        currentTemplateVersionID = model.currentTemplateVersionID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func makeModel() -> TrainingProgram {
        TrainingProgram(
            id: id,
            name: name,
            goal: goal,
            status: TrainingProgramStatus(rawValue: statusRaw) ?? .active,
            currentTemplateVersionID: currentTemplateVersionID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct WorkoutTemplateVersionDTO: Codable, Equatable, Sendable {
    var id: UUID
    var programID: UUID
    var familyID: UUID
    var version: Int
    var name: String
    var scheduleHint: String
    var source: String
    var createdAt: Date
    var changeSummary: String?
    var changeDetails: String?

    init(_ model: WorkoutTemplateVersion) {
        id = model.id
        programID = model.programID
        familyID = model.familyID
        version = model.version
        name = model.name
        scheduleHint = model.scheduleHint
        source = model.source
        createdAt = model.createdAt
        changeSummary = model.changeSummary
        changeDetails = model.changeDetails
    }

    func makeModel() -> WorkoutTemplateVersion {
        WorkoutTemplateVersion(
            id: id,
            programID: programID,
            familyID: familyID,
            version: version,
            name: name,
            scheduleHint: scheduleHint,
            source: source,
            createdAt: createdAt,
            changeSummary: changeSummary,
            changeDetails: changeDetails
        )
    }
}

struct TemplateExerciseDTO: Codable, Equatable, Sendable {
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

    init(_ model: TemplateExercise) {
        id = model.id
        templateVersionID = model.templateVersionID
        exerciseID = model.exerciseID
        order = model.order
        targetSets = model.targetSets
        targetReps = model.targetReps
        targetWeightKG = model.targetWeightKG
        targetRestSeconds = model.targetRestSeconds
        firstSetIsWarmup = model.firstSetIsWarmup
        equipmentKind = model.equipmentKind
        notes = model.notes
    }

    func makeModel() -> TemplateExercise {
        TemplateExercise(
            id: id,
            templateVersionID: templateVersionID,
            exerciseID: exerciseID,
            order: order,
            targetSets: targetSets,
            targetReps: targetReps,
            targetWeightKG: targetWeightKG,
            targetRestSeconds: targetRestSeconds,
            firstSetIsWarmup: firstSetIsWarmup,
            equipmentKind: equipmentKind,
            notes: notes
        )
    }
}

struct WorkoutSessionDTO: Codable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var gymID: UUID?
    var programID: UUID?
    var programNameSnapshot: String?
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

    init(_ model: WorkoutSession) {
        id = model.id
        startedAt = model.startedAt
        endedAt = model.endedAt
        gymID = model.gymID
        programID = model.programID
        programNameSnapshot = model.programNameSnapshot
        sourceTemplateFamilyID = model.sourceTemplateFamilyID
        sourceTemplateVersion = model.sourceTemplateVersion
        prescriptionSnapshotData = model.prescriptionSnapshotData
        statusRaw = model.statusRaw
        guidedPhaseRaw = model.guidedPhaseRaw
        currentPerformanceID = model.currentPerformanceID
        currentSetID = model.currentSetID
        phaseStartedAt = model.phaseStartedAt
        restStartedAt = model.restStartedAt
        restTargetEndAt = model.restTargetEndAt
        autoRecordingPolicyRaw = model.autoRecordingPolicyRaw
        sourceTurnID = model.sourceTurnID
        sourceJobID = model.sourceJobID
    }

    func makeModel() -> WorkoutSession {
        let model = WorkoutSession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            gymID: gymID,
            programID: programID,
            programNameSnapshot: programNameSnapshot,
            sourceTemplateFamilyID: sourceTemplateFamilyID,
            sourceTemplateVersion: sourceTemplateVersion,
            prescriptionSnapshot: TrainingPlanCoding.decode(
                [TemplateExercisePrescription].self,
                from: prescriptionSnapshotData
            ) ?? [],
            status: WorkoutSessionStatus(rawValue: statusRaw) ?? .draft,
            guidedPhase: GuidedWorkoutPhase(rawValue: guidedPhaseRaw) ?? .ready,
            currentPerformanceID: currentPerformanceID,
            currentSetID: currentSetID,
            phaseStartedAt: phaseStartedAt,
            restStartedAt: restStartedAt,
            restTargetEndAt: restTargetEndAt,
            autoRecordingPolicy: AutoRecordingPolicy(
                rawValue: autoRecordingPolicyRaw
            ) ?? .disabled,
            sourceTurnID: sourceTurnID,
            sourceJobID: sourceJobID
        )
        model.prescriptionSnapshotData = prescriptionSnapshotData
        return model
    }
}

struct ExercisePerformanceDTO: Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var prescriptionSnapshotData: Data
    var statusRaw: String
    var notes: String
    var activeVideoPath: String?
    var workoutProjectionSuppressed: Bool?

    init(_ model: ExercisePerformance) {
        id = model.id
        sessionID = model.sessionID
        exerciseID = model.exerciseID
        exerciseName = model.exerciseName
        order = model.order
        prescriptionSnapshotData = model.prescriptionSnapshotData
        statusRaw = model.statusRaw
        notes = model.notes
        activeVideoPath = model.activeVideoPath
        workoutProjectionSuppressed = model.workoutProjectionSuppressed
    }

    func makeModel(
        mediaPathMapping: [String: String]
    ) -> ExercisePerformance {
        let snapshot = TrainingPlanCoding.decode(
            TemplateExercisePrescription.self,
            from: prescriptionSnapshotData
        ) ?? TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            order: order
        )
        let model = ExercisePerformance(
            id: id,
            sessionID: sessionID,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            order: order,
            prescriptionSnapshot: snapshot,
            status: ExercisePerformanceStatus(rawValue: statusRaw) ?? .pending,
            notes: notes,
            activeVideoPath: mapped(activeVideoPath, with: mediaPathMapping),
            workoutProjectionSuppressed: workoutProjectionSuppressed ?? false
        )
        model.prescriptionSnapshotData = prescriptionSnapshotData
        return model
    }
}

struct WorkoutSetDTO: Codable, Equatable, Sendable {
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

    init(_ model: WorkoutSet) {
        id = model.id
        performanceID = model.performanceID
        order = model.order
        kindRaw = model.kindRaw
        laterality = model.laterality
        plannedReps = model.plannedReps
        plannedWeightKG = model.plannedWeightKG
        plannedRestSeconds = model.plannedRestSeconds
        actualReps = model.actualReps
        actualWeightKG = model.actualWeightKG
        actualRestSeconds = model.actualRestSeconds
        statusRaw = model.statusRaw
        startedAt = model.startedAt
        completedAt = model.completedAt
        recordedVideoPath = model.recordedVideoPath
    }

    func makeModel(mediaPathMapping: [String: String]) -> WorkoutSet {
        WorkoutSet(
            id: id,
            performanceID: performanceID,
            order: order,
            kind: WorkoutSetKind(rawValue: kindRaw) ?? .working,
            laterality: laterality,
            plannedReps: plannedReps,
            plannedWeightKG: plannedWeightKG,
            plannedRestSeconds: plannedRestSeconds,
            actualReps: actualReps,
            actualWeightKG: actualWeightKG,
            actualRestSeconds: actualRestSeconds,
            status: WorkoutSetStatus(rawValue: statusRaw) ?? .pending,
            startedAt: startedAt,
            completedAt: completedAt,
            recordedVideoPath: mapped(
                recordedVideoPath,
                with: mediaPathMapping
            )
        )
    }
}

struct RecommendationSnapshotDTO: Codable, Equatable, Sendable {
    var id: UUID
    var targetKind: String
    var targetID: UUID
    var inputFingerprint: String
    var advice: String
    var createdAt: Date
    var sourceJobID: UUID?

    init(_ model: RecommendationSnapshot) {
        id = model.id
        targetKind = model.targetKind
        targetID = model.targetID
        inputFingerprint = model.inputFingerprint
        advice = model.advice
        createdAt = model.createdAt
        sourceJobID = model.sourceJobID
    }

    func makeModel() -> RecommendationSnapshot {
        RecommendationSnapshot(
            id: id,
            targetKind: targetKind,
            targetID: targetID,
            inputFingerprint: inputFingerprint,
            advice: advice,
            createdAt: createdAt,
            sourceJobID: sourceJobID
        )
    }
}

struct PerformanceAnalysisDTO: Codable, Equatable, Sendable {
    var id: UUID
    var performanceID: UUID
    var sourceMediaPath: String
    var inputFingerprint: String
    var evidence: String
    var limitations: String
    var feedback: String
    var createdAt: Date
    var sourceJobID: UUID?

    init(_ model: PerformanceAnalysis) {
        id = model.id
        performanceID = model.performanceID
        sourceMediaPath = model.sourceMediaPath
        inputFingerprint = model.inputFingerprint
        evidence = model.evidence
        limitations = model.limitations
        feedback = model.feedback
        createdAt = model.createdAt
        sourceJobID = model.sourceJobID
    }

    func makeModel(
        mediaPathMapping: [String: String]
    ) -> PerformanceAnalysis {
        PerformanceAnalysis(
            id: id,
            performanceID: performanceID,
            sourceMediaPath: mapped(sourceMediaPath, with: mediaPathMapping) ?? "",
            inputFingerprint: inputFingerprint,
            evidence: evidence,
            limitations: limitations,
            feedback: feedback,
            createdAt: createdAt,
            sourceJobID: sourceJobID
        )
    }
}
