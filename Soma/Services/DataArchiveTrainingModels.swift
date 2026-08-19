import Foundation

struct TrainingProgramDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var name: String
    var goal: String
    var statusRaw: String
    var currentTemplateVersionID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ model: TrainingProgram) {
        id = model.id
        businessID = model.businessID
        name = model.name
        goal = model.overview
        statusRaw = model.statusRaw
        currentTemplateVersionID = model.currentTemplateVersionID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    func makeModel() -> TrainingProgram {
        let model = TrainingProgram(
            id: id,
            name: name,
            overview: goal,
            status: TrainingProgramStatus(rawValue: statusRaw) ?? .active,
            currentTemplateVersionID: currentTemplateVersionID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        model.businessID = businessID
        return model
    }
}

struct WorkoutTemplateVersionDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
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
        businessID = model.businessID
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
        let model = WorkoutTemplateVersion(
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
        model.businessID = businessID
        return model
    }
}

struct TemplateExerciseDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
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
    var lateralityRaw: String?

    init(_ model: TemplateExercise) {
        id = model.id
        businessID = model.businessID
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
        lateralityRaw = model.lateralityRaw
    }

    func makeModel() -> TemplateExercise {
        let model = TemplateExercise(
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
            notes: notes,
            laterality: lateralityRaw.flatMap(ExerciseLaterality.init(rawValue:))
                ?? .none
        )
        model.businessID = businessID
        return model
    }
}

struct TemplateSetPrescriptionDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var templateExerciseID: UUID
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

    init(_ model: TemplateSetPrescription) {
        id = model.id
        businessID = model.businessID
        templateExerciseID = model.templateExerciseID
        order = model.order
        kindRaw = model.kindRaw
        targetKindRaw = model.targetKindRaw
        targetReps = model.targetReps
        targetDurationSeconds = model.targetDurationSeconds
        targetWeightKG = model.targetWeightKG
        leftWeightKG = model.leftWeightKG
        rightWeightKG = model.rightWeightKG
        restBetweenSidesSeconds = model.restBetweenSidesSeconds
        restAfterSetSeconds = model.restAfterSetSeconds
        notes = model.notes
    }

    func makeModel() -> TemplateSetPrescription {
        let model = TemplateSetPrescription(
            id: id,
            templateExerciseID: templateExerciseID,
            order: order,
            kind: WorkoutSetKind(rawValue: kindRaw) ?? .working,
            targetKind: WorkoutTargetKind(rawValue: targetKindRaw) ?? .repetitions,
            targetReps: targetReps,
            targetDurationSeconds: targetDurationSeconds,
            targetWeightKG: targetWeightKG,
            leftWeightKG: leftWeightKG,
            rightWeightKG: rightWeightKG,
            restBetweenSidesSeconds: restBetweenSidesSeconds,
            restAfterSetSeconds: restAfterSetSeconds,
            notes: notes
        )
        model.businessID = businessID
        return model
    }
}

struct WorkoutSessionDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
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
    var currentEffortID: UUID?
    var phaseStartedAt: Date?
    var phaseDeadlineAt: Date?
    var transitionRevision: Int?
    var restStartedAt: Date?
    var restTargetEndAt: Date?
    var autoRecordingPolicyRaw: String
    var queuedRecordingEffortID: UUID?
    var automaticRecordingPaused: Bool?
    var automaticRecordingPauseCodeRaw: String?
    var automaticRecordingPauseReason: String?
    var sourceTurnID: UUID?
    var sourceJobID: UUID?

    init(_ model: WorkoutSession) {
        id = model.id
        businessID = model.businessID
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
        currentEffortID = model.currentEffortID
        phaseStartedAt = model.phaseStartedAt
        phaseDeadlineAt = model.phaseDeadlineAt
        transitionRevision = model.transitionRevision
        restStartedAt = model.restStartedAt
        restTargetEndAt = model.restTargetEndAt
        autoRecordingPolicyRaw = model.autoRecordingPolicyRaw
        queuedRecordingEffortID = model.queuedRecordingEffortID
        automaticRecordingPaused = model.automaticRecordingPaused
        automaticRecordingPauseCodeRaw = model.automaticRecordingPauseCodeRaw
        automaticRecordingPauseReason = model.automaticRecordingPauseReason
        sourceTurnID = model.sourceTurnID
        sourceJobID = model.sourceJobID
    }

    func makeModel() throws -> WorkoutSession {
        guard let snapshot = TrainingPlanCoding.decode(
            [TemplateExercisePrescription].self,
            from: prescriptionSnapshotData
        ) else {
            throw DataArchiveError.invalidSnapshot
        }
        let model = WorkoutSession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            gymID: gymID,
            programID: programID,
            programNameSnapshot: programNameSnapshot,
            sourceTemplateFamilyID: sourceTemplateFamilyID,
            sourceTemplateVersion: sourceTemplateVersion,
            prescriptionSnapshot: snapshot,
            status: WorkoutSessionStatus(rawValue: statusRaw) ?? .draft,
            guidedPhase: GuidedWorkoutPhase(rawValue: guidedPhaseRaw) ?? .ready,
            currentPerformanceID: currentPerformanceID,
            currentSetID: currentSetID,
            currentEffortID: currentEffortID,
            phaseStartedAt: phaseStartedAt,
            phaseDeadlineAt: phaseDeadlineAt,
            transitionRevision: transitionRevision ?? 0,
            restStartedAt: restStartedAt,
            restTargetEndAt: restTargetEndAt,
            autoRecordingPolicy: AutoRecordingPolicy(
                rawValue: autoRecordingPolicyRaw
            ) ?? .disabled,
            queuedRecordingEffortID: queuedRecordingEffortID,
            automaticRecordingPaused: automaticRecordingPaused ?? false,
            automaticRecordingPauseCode: automaticRecordingPauseCodeRaw.flatMap(
                WorkoutRecordingPauseCode.init(rawValue:)
            ),
            automaticRecordingPauseReason: automaticRecordingPauseReason,
            sourceTurnID: sourceTurnID,
            sourceJobID: sourceJobID
        )
        model.businessID = businessID
        model.prescriptionSnapshotData = prescriptionSnapshotData
        return model
    }
}

struct ExercisePerformanceDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var sessionID: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var prescriptionSnapshotData: Data
    var statusRaw: String
    var notes: String
    var activeVideoPath: String?
    var activeVideoKindRaw: String?
    var workoutProjectionSuppressed: Bool?

    init(_ model: ExercisePerformance) {
        id = model.id
        businessID = model.businessID
        sessionID = model.sessionID
        exerciseID = model.exerciseID
        exerciseName = model.exerciseName
        order = model.order
        prescriptionSnapshotData = model.prescriptionSnapshotData
        statusRaw = model.statusRaw
        notes = model.notes
        activeVideoPath = model.activeVideoPath
        activeVideoKindRaw = model.activeVideoKindRaw
        workoutProjectionSuppressed = model.workoutProjectionSuppressed
    }

    func makeModel(
        mediaPathMapping: [String: String]
    ) throws -> ExercisePerformance {
        guard let snapshot = TrainingPlanCoding.decode(
            TemplateExercisePrescription.self,
            from: prescriptionSnapshotData
        ) else {
            throw DataArchiveError.invalidSnapshot
        }
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
            activeVideoKind: activeVideoKindRaw.flatMap(
                WorkoutRecordingEvidenceKind.init(rawValue:)
            ),
            workoutProjectionSuppressed: workoutProjectionSuppressed ?? false
        )
        model.businessID = businessID
        model.prescriptionSnapshotData = prescriptionSnapshotData
        return model
    }
}

struct WorkoutSetDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var performanceID: UUID
    var order: Int
    var kindRaw: String
    var laterality: String?
    var plannedReps: Int?
    var plannedTargetKindRaw: String?
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

    init(_ model: WorkoutSet) {
        id = model.id
        businessID = model.businessID
        performanceID = model.performanceID
        order = model.order
        kindRaw = model.kindRaw
        laterality = model.laterality
        plannedReps = model.plannedReps
        plannedTargetKindRaw = model.plannedTargetKindRaw
        plannedDurationSeconds = model.plannedDurationSeconds
        plannedWeightKG = model.plannedWeightKG
        plannedRestSeconds = model.plannedRestSeconds
        restBetweenSidesSeconds = model.restBetweenSidesSeconds
        actualReps = model.actualReps
        actualDurationSeconds = model.actualDurationSeconds
        actualWeightKG = model.actualWeightKG
        actualRestSeconds = model.actualRestSeconds
        statusRaw = model.statusRaw
        startedAt = model.startedAt
        completedAt = model.completedAt
        recordedVideoPath = model.recordedVideoPath
        recordedVideoKindRaw = model.recordedVideoKindRaw
    }

    func makeModel(mediaPathMapping: [String: String]) -> WorkoutSet {
        let model = WorkoutSet(
            id: id,
            performanceID: performanceID,
            order: order,
            kind: WorkoutSetKind(rawValue: kindRaw) ?? .working,
            laterality: laterality,
            plannedTargetKind: plannedTargetKindRaw.flatMap(
                WorkoutTargetKind.init(rawValue:)
            ) ?? .repetitions,
            plannedReps: plannedReps,
            plannedDurationSeconds: plannedDurationSeconds,
            plannedWeightKG: plannedWeightKG,
            plannedRestSeconds: plannedRestSeconds,
            restBetweenSidesSeconds: restBetweenSidesSeconds,
            actualReps: actualReps,
            actualDurationSeconds: actualDurationSeconds,
            actualWeightKG: actualWeightKG,
            actualRestSeconds: actualRestSeconds,
            status: WorkoutSetStatus(rawValue: statusRaw) ?? .pending,
            startedAt: startedAt,
            completedAt: completedAt,
            recordedVideoPath: mapped(
                recordedVideoPath,
                with: mediaPathMapping
            ),
            recordedVideoKind: recordedVideoKindRaw.flatMap(
                WorkoutRecordingEvidenceKind.init(rawValue:)
            )
        )
        model.businessID = businessID
        return model
    }
}

struct WorkoutEffortDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var workoutSetID: UUID
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

    init(_ model: WorkoutEffort) {
        id = model.id
        businessID = model.businessID
        workoutSetID = model.workoutSetID
        order = model.order
        sideRaw = model.sideRaw
        targetKindRaw = model.targetKindRaw
        plannedReps = model.plannedReps
        plannedDurationSeconds = model.plannedDurationSeconds
        plannedWeightKG = model.plannedWeightKG
        actualReps = model.actualReps
        actualDurationSeconds = model.actualDurationSeconds
        actualWeightKG = model.actualWeightKG
        actualRestSeconds = model.actualRestSeconds
        statusRaw = model.statusRaw
        startedAt = model.startedAt
        completedAt = model.completedAt
        recordedVideoPath = model.recordedVideoPath
        recordedVideoKindRaw = model.recordedVideoKindRaw
    }

    func makeModel(mediaPathMapping: [String: String]) -> WorkoutEffort {
        let model = WorkoutEffort(
            id: id,
            workoutSetID: workoutSetID,
            order: order,
            side: WorkoutEffortSide(rawValue: sideRaw) ?? .none,
            targetKind: WorkoutTargetKind(rawValue: targetKindRaw) ?? .repetitions,
            plannedReps: plannedReps,
            plannedDurationSeconds: plannedDurationSeconds,
            plannedWeightKG: plannedWeightKG,
            actualReps: actualReps,
            actualDurationSeconds: actualDurationSeconds,
            actualWeightKG: actualWeightKG,
            actualRestSeconds: actualRestSeconds,
            status: WorkoutEffortStatus(rawValue: statusRaw) ?? .pending,
            startedAt: startedAt,
            completedAt: completedAt,
            recordedVideoPath: mapped(recordedVideoPath, with: mediaPathMapping),
            recordedVideoKind: recordedVideoKindRaw.flatMap(
                WorkoutRecordingEvidenceKind.init(rawValue:)
            )
        )
        model.businessID = businessID
        return model
    }
}

struct RecommendationSnapshotDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var targetKind: String
    var targetID: UUID
    var inputFingerprint: String
    var advice: String
    var createdAt: Date
    var sourceJobID: UUID?

    init(_ model: RecommendationSnapshot) {
        id = model.id
        businessID = model.businessID
        targetKind = model.targetKind
        targetID = model.targetID
        inputFingerprint = model.inputFingerprint
        advice = model.advice
        createdAt = model.createdAt
        sourceJobID = model.sourceJobID
    }

    func makeModel() -> RecommendationSnapshot {
        let model = RecommendationSnapshot(
            id: id,
            targetKind: targetKind,
            targetID: targetID,
            inputFingerprint: inputFingerprint,
            advice: advice,
            createdAt: createdAt,
            sourceJobID: sourceJobID
        )
        model.businessID = businessID
        return model
    }
}

struct PerformanceAnalysisDTO: Codable, Equatable, Sendable {
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

    init(_ model: PerformanceAnalysis) {
        id = model.id
        businessID = model.businessID
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
        let model = PerformanceAnalysis(
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
        model.businessID = businessID
        return model
    }
}
