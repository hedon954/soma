import Foundation
import SwiftData

struct PersonalDataSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 6

    var schemaVersion = Self.currentSchemaVersion
    var createdAt: Date
    var externalSyncCursors: [ExternalSyncCursorDTO]
    var userProfiles: [UserProfileDTO]
    var gymProfiles: [GymProfileDTO]
    var gymEquipment: [GymEquipmentDTO]
    var gymMedia: [GymMediaDTO]
    var meals: [MealEntryDTO]
    var bodyEntries: [BodyEntryDTO]
    var exerciseDefinitions: [ExerciseDefinitionDTO]?
    var exerciseMergeRecords: [ExerciseMergeRecordDTO]?
    var workouts: [WorkoutEntryDTO]
    var trainingPrograms: [TrainingProgramDTO]?
    var templateExercises: [TemplateExerciseDTO]?
    var templateSetPrescriptions: [TemplateSetPrescriptionDTO]?
    var workoutSessions: [WorkoutSessionDTO]?
    var exercisePerformances: [ExercisePerformanceDTO]?
    var workoutSets: [WorkoutSetDTO]?
    var workoutEfforts: [WorkoutEffortDTO]?
    var recommendationSnapshots: [RecommendationSnapshotDTO]?
    var performanceAnalyses: [PerformanceAnalysisDTO]?
    var sessions: [ConversationSessionDTO]
    var messages: [CoachMessageDTO]
    var traces: [AgentTraceDTO]
    var mutationReceipts: [AgentMutationReceiptDTO]
    var agentJobs: [AgentJobDTO]?
    var agentEvents: [PersistentAgentEventDTO]?

    var referencedMediaPaths: Set<String> {
        var paths = Set<String>()
        gymProfiles.compactMap(\.coverImagePath).forEach { paths.insert($0) }
        gymEquipment.compactMap(\.imagePath).forEach { paths.insert($0) }
        gymMedia.map(\.path).forEach { paths.insert($0) }
        meals.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        bodyEntries.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        for item in (exerciseDefinitions ?? []).flatMap(\.referencedMediaPaths) {
            paths.insert(item)
        }
        for item in (exerciseMergeRecords ?? []).flatMap(\.referencedMediaPaths) {
            paths.insert(item)
        }
        workouts.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        (exercisePerformances ?? []).compactMap(\.activeVideoPath)
            .forEach { paths.insert($0) }
        (workoutSets ?? []).compactMap(\.recordedVideoPath)
            .forEach { paths.insert($0) }
        (workoutEfforts ?? []).compactMap(\.recordedVideoPath)
            .forEach { paths.insert($0) }
        (performanceAnalyses ?? []).map(\.sourceMediaPath)
            .filter { !$0.isEmpty }
            .forEach { paths.insert($0) }
        messages.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        for item in (agentJobs ?? []).flatMap(\.mediaAttachments).map(\.path) {
            paths.insert(item)
        }
        return paths.filter { !$0.isEmpty }
    }

    func validate() throws {
        guard (1 ... Self.currentSchemaVersion).contains(schemaVersion) else {
            throw DataArchiveError.unsupportedSchema(schemaVersion)
        }
        guard mutationReceipts.allSatisfy(\.hasDecodableResult) else {
            throw DataArchiveError.invalidSnapshot
        }
        guard (workoutSessions ?? []).allSatisfy({
            TrainingPlanCoding.decode(
                [TemplateExercisePrescription].self,
                from: $0.prescriptionSnapshotData
            ) != nil
        }) else {
            throw DataArchiveError.invalidSnapshot
        }
        guard (exercisePerformances ?? []).allSatisfy({
            TrainingPlanCoding.decode(
                TemplateExercisePrescription.self,
                from: $0.prescriptionSnapshotData
            ) != nil
        }) else {
            throw DataArchiveError.invalidSnapshot
        }
    }

    @MainActor
    static func capture(
        from context: ModelContext,
        now: Date = .now
    ) throws -> PersonalDataSnapshot {
        try PersonalDataSnapshot(
            createdAt: now,
            externalSyncCursors: context.fetch(FetchDescriptor<ExternalSyncCursor>())
                .map(ExternalSyncCursorDTO.init),
            userProfiles: context.fetch(FetchDescriptor<UserProfile>())
                .map(UserProfileDTO.init),
            gymProfiles: context.fetch(FetchDescriptor<GymProfile>())
                .map(GymProfileDTO.init),
            gymEquipment: context.fetch(FetchDescriptor<GymEquipment>())
                .map(GymEquipmentDTO.init),
            gymMedia: context.fetch(FetchDescriptor<GymMedia>())
                .map(GymMediaDTO.init),
            meals: context.fetch(FetchDescriptor<MealEntry>())
                .map(MealEntryDTO.init),
            bodyEntries: context.fetch(FetchDescriptor<BodyEntry>())
                .map(BodyEntryDTO.init),
            exerciseDefinitions: context.fetch(FetchDescriptor<ExerciseDefinition>())
                .map(ExerciseDefinitionDTO.init),
            exerciseMergeRecords: context.fetch(FetchDescriptor<ExerciseMergeRecord>())
                .map(ExerciseMergeRecordDTO.init),
            workouts: context.fetch(FetchDescriptor<WorkoutEntry>())
                .map(WorkoutEntryDTO.init),
            trainingPrograms: context.fetch(FetchDescriptor<TrainingProgram>())
                .map(TrainingProgramDTO.init),
            templateExercises: context.fetch(FetchDescriptor<TemplateExercise>())
                .map(TemplateExerciseDTO.init),
            templateSetPrescriptions: context.fetch(
                FetchDescriptor<TemplateSetPrescription>()
            ).map(TemplateSetPrescriptionDTO.init),
            workoutSessions: context.fetch(FetchDescriptor<WorkoutSession>())
                .map(WorkoutSessionDTO.init),
            exercisePerformances: context.fetch(
                FetchDescriptor<ExercisePerformance>()
            ).map(ExercisePerformanceDTO.init),
            workoutSets: context.fetch(FetchDescriptor<WorkoutSet>())
                .map(WorkoutSetDTO.init),
            workoutEfforts: context.fetch(FetchDescriptor<WorkoutEffort>())
                .map(WorkoutEffortDTO.init),
            recommendationSnapshots: context.fetch(
                FetchDescriptor<RecommendationSnapshot>()
            ).map(RecommendationSnapshotDTO.init),
            performanceAnalyses: context.fetch(
                FetchDescriptor<PerformanceAnalysis>()
            ).map(PerformanceAnalysisDTO.init),
            sessions: context.fetch(FetchDescriptor<ConversationSession>())
                .map(ConversationSessionDTO.init),
            messages: context.fetch(FetchDescriptor<CoachMessage>())
                .map(CoachMessageDTO.init),
            traces: context.fetch(FetchDescriptor<AgentTrace>())
                .map(AgentTraceDTO.init),
            mutationReceipts: context.fetch(FetchDescriptor<AgentMutationReceipt>())
                .map(AgentMutationReceiptDTO.init),
            agentJobs: context.fetch(FetchDescriptor<AgentJob>())
                .map(AgentJobDTO.init),
            agentEvents: context.fetch(FetchDescriptor<PersistentAgentEvent>())
                .map(PersistentAgentEventDTO.init)
        )
    }

    @MainActor
    func replace(
        in context: ModelContext,
        mediaPathMapping: [String: String]
    ) throws {
        try validate()
        try context.transaction {
            try PersonalDataStore.deleteAllModels(in: context)
            insertProfileModels(
                in: context,
                mediaPathMapping: mediaPathMapping
            )
            try insertTrainingModels(
                in: context,
                mediaPathMapping: mediaPathMapping
            )
            try insertConversationModels(
                in: context,
                mediaPathMapping: mediaPathMapping
            )
            try BusinessIDAllocator.repairAndAssignAllIDs(in: context)
            ExerciseLibraryStore.migrateLegacyWorkoutNames(in: context)
            try SomaDataMigration.repairExerciseRelationships(in: context)
            try SomaDataMigration.repairTrainingRelationships(in: context)
            try context.save()
        }
    }

    @MainActor
    private func insertProfileModels(
        in context: ModelContext,
        mediaPathMapping: [String: String]
    ) {
        externalSyncCursors.forEach { context.insert($0.makeModel()) }
        userProfiles.forEach { context.insert($0.makeModel()) }
        for profile in gymProfiles {
            context.insert(profile.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for equipment in gymEquipment {
            context.insert(equipment.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for media in gymMedia {
            context.insert(media.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for meal in meals {
            context.insert(meal.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for entry in bodyEntries {
            context.insert(entry.makeModel(mediaPathMapping: mediaPathMapping))
        }
    }

    @MainActor
    private func insertTrainingModels(
        in context: ModelContext,
        mediaPathMapping: [String: String]
    ) throws {
        for definition in exerciseDefinitions ?? [] {
            context.insert(definition.makeModel(
                mediaPathMapping: mediaPathMapping
            ))
        }
        for mergeRecord in exerciseMergeRecords ?? [] {
            context.insert(mergeRecord.makeModel(
                mediaPathMapping: mediaPathMapping
            ))
        }
        for workout in workouts {
            context.insert(workout.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for program in trainingPrograms ?? [] {
            context.insert(program.makeModel())
        }
        for item in templateExercises ?? [] {
            context.insert(item.makeModel())
        }
        for item in templateSetPrescriptions ?? [] {
            context.insert(item.makeModel())
        }
        for session in workoutSessions ?? [] {
            try context.insert(session.makeModel())
        }
        for performance in exercisePerformances ?? [] {
            try context.insert(performance.makeModel(
                mediaPathMapping: mediaPathMapping
            ))
        }
        for set in workoutSets ?? [] {
            context.insert(set.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for effort in workoutEfforts ?? [] {
            context.insert(effort.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for recommendation in recommendationSnapshots ?? [] {
            context.insert(recommendation.makeModel())
        }
        for analysis in performanceAnalyses ?? [] {
            context.insert(analysis.makeModel(
                mediaPathMapping: mediaPathMapping
            ))
        }
    }

    @MainActor
    private func insertConversationModels(
        in context: ModelContext,
        mediaPathMapping: [String: String]
    ) throws {
        sessions.forEach { context.insert($0.makeModel()) }
        for message in messages {
            context.insert(message.makeModel(mediaPathMapping: mediaPathMapping))
        }
        traces.forEach { context.insert($0.makeModel()) }
        for receipt in mutationReceipts {
            try context.insert(receipt.makeModel())
        }
        for job in agentJobs ?? [] {
            context.insert(job.makeModel(mediaPathMapping: mediaPathMapping))
        }
        for event in agentEvents ?? [] {
            context.insert(event.makeModel())
        }
    }
}

struct ExternalSyncCursorDTO: Codable, Equatable, Sendable {
    var id: UUID
    var source: String
    var stream: String
    var cursorData: Data?
    var updatedAt: Date

    init(_ model: ExternalSyncCursor) {
        id = model.id
        source = model.source
        stream = model.stream
        cursorData = model.cursorData
        updatedAt = model.updatedAt
    }

    func makeModel() -> ExternalSyncCursor {
        let model = ExternalSyncCursor(
            source: source,
            stream: stream,
            cursorData: cursorData,
            updatedAt: updatedAt
        )
        model.id = id
        return model
    }
}

struct UserProfileDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var updatedAt: Date
    var displayName: String
    var biologicalSexRaw: String
    var birthDate: Date?
    var age: Int?
    var height: Double?
    var referenceWeight: Double?
    var fitnessGoal: String
    var healthNotes: String

    init(_ model: UserProfile) {
        id = model.id
        businessID = model.businessID
        updatedAt = model.updatedAt
        displayName = model.displayName
        biologicalSexRaw = model.biologicalSexRaw
        birthDate = model.birthDate
        age = model.age
        height = model.height
        referenceWeight = model.referenceWeight
        fitnessGoal = model.fitnessGoal
        healthNotes = model.healthNotes
    }

    func makeModel() -> UserProfile {
        let model = UserProfile(
            updatedAt: updatedAt,
            displayName: displayName,
            biologicalSex: BiologicalSex(rawValue: biologicalSexRaw) ?? .unspecified,
            birthDate: birthDate,
            age: age,
            height: height,
            referenceWeight: referenceWeight,
            fitnessGoal: fitnessGoal,
            healthNotes: healthNotes
        )
        model.id = id
        model.businessID = businessID
        model.biologicalSexRaw = biologicalSexRaw
        return model
    }
}

struct GymProfileDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var name: String
    var createdAt: Date
    var notes: String
    var coverImagePath: String?
    var isCurrent: Bool
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?
    var locationAccuracy: Double?
    var locationUpdatedAt: Date?
    var matchRadiusMeters: Double

    init(_ model: GymProfile) {
        id = model.id
        businessID = model.businessID
        name = model.name
        createdAt = model.createdAt
        notes = model.notes
        coverImagePath = model.coverImagePath
        isCurrent = model.isCurrent
        latitude = model.latitude
        longitude = model.longitude
        locationLabel = model.locationLabel
        locationAccuracy = model.locationAccuracy
        locationUpdatedAt = model.locationUpdatedAt
        matchRadiusMeters = model.matchRadiusMeters
    }

    func makeModel(mediaPathMapping: [String: String]) -> GymProfile {
        let model = GymProfile(
            name: name,
            notes: notes,
            coverImagePath: mapped(coverImagePath, with: mediaPathMapping),
            isCurrent: isCurrent,
            latitude: latitude,
            longitude: longitude,
            locationLabel: locationLabel,
            locationAccuracy: locationAccuracy,
            locationUpdatedAt: locationUpdatedAt,
            matchRadiusMeters: matchRadiusMeters
        )
        model.id = id
        model.businessID = businessID
        model.createdAt = createdAt
        return model
    }
}

struct GymEquipmentDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var gymID: UUID
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double
    var imagePath: String?
    var createdAt: Date

    init(_ model: GymEquipment) {
        id = model.id
        businessID = model.businessID
        gymID = model.gymID
        name = model.name
        category = model.category
        capabilities = model.capabilities
        confidence = model.confidence
        imagePath = model.imagePath
        createdAt = model.createdAt
    }

    func makeModel(mediaPathMapping: [String: String]) -> GymEquipment {
        let model = GymEquipment(
            gymID: gymID,
            name: name,
            category: category,
            capabilities: capabilities,
            confidence: confidence,
            imagePath: mapped(imagePath, with: mediaPathMapping)
        )
        model.id = id
        model.businessID = businessID
        model.createdAt = createdAt
        return model
    }
}

struct GymMediaDTO: Codable, Equatable, Sendable {
    var id: UUID
    var gymID: UUID
    var path: String
    var createdAt: Date

    init(_ model: GymMedia) {
        id = model.id
        gymID = model.gymID
        path = model.path
        createdAt = model.createdAt
    }

    func makeModel(mediaPathMapping: [String: String]) -> GymMedia {
        let model = GymMedia(
            gymID: gymID,
            path: mediaPathMapping[path] ?? path,
            createdAt: createdAt
        )
        model.id = id
        return model
    }
}

struct MealEntryDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var date: Date
    var mealTypeRaw: String
    var title: String
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var totalSugar: Double?
    var glycemicSpeedRaw: String?
    var glycemicAssessment: String?
    var items: [MealItem]?
    var nutritionSourceRaw: String?
    var notes: String
    var mediaAttachments: [MediaAttachmentReference]
    var confidence: Double
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    init(_ model: MealEntry) {
        id = model.id
        businessID = model.businessID
        date = model.date
        mealTypeRaw = model.mealTypeRaw
        title = model.title
        calories = model.calories
        protein = model.protein
        carbs = model.carbs
        fat = model.fat
        totalSugar = model.totalSugar
        glycemicSpeedRaw = model.glycemicSpeedRaw
        glycemicAssessment = model.glycemicAssessment.isEmpty
            ? nil
            : model.glycemicAssessment
        items = model.items
        nutritionSourceRaw = model.nutritionSourceRaw
        notes = model.notes
        mediaAttachments = model.mediaAttachments
        confidence = model.confidence
        sourceTurnID = model.sourceTurnID
        sourceSessionID = model.sourceSessionID
    }

    func makeModel(mediaPathMapping: [String: String]) -> MealEntry {
        let attachments = mapped(mediaAttachments, with: mediaPathMapping)
        let model = MealEntry(
            date: date,
            mealType: MealType(rawValue: mealTypeRaw) ?? .lunch,
            title: title,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            totalSugar: totalSugar,
            glycemicSpeed: glycemicSpeedRaw.flatMap(MealGlycemicSpeed.init(rawValue:)),
            glycemicAssessment: glycemicAssessment ?? "",
            items: items ?? [],
            nutritionSource: nutritionSourceRaw
                .flatMap(MealNutritionSource.init(rawValue:)) ?? .imported,
            notes: notes,
            mediaAttachments: attachments,
            confidence: confidence,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        )
        model.id = id
        model.businessID = businessID
        model.mealTypeRaw = mealTypeRaw
        return model
    }
}

struct BodyEntryDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var date: Date
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var notes: String
    var mediaAttachments: [MediaAttachmentReference]
    var analysis: String
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    init(_ model: BodyEntry) {
        id = model.id
        businessID = model.businessID
        date = model.date
        weight = model.weight
        bodyFat = model.bodyFat
        waist = model.waist
        notes = model.notes
        mediaAttachments = model.mediaAttachments
        analysis = model.analysis
        externalSource = model.externalSource
        externalID = model.externalID
        sourceTurnID = model.sourceTurnID
        sourceSessionID = model.sourceSessionID
    }

    func makeModel(mediaPathMapping: [String: String]) -> BodyEntry {
        let model = BodyEntry(
            date: date,
            weight: weight,
            bodyFat: bodyFat,
            waist: waist,
            notes: notes,
            mediaAttachments: mapped(mediaAttachments, with: mediaPathMapping),
            analysis: analysis,
            externalSource: externalSource,
            externalID: externalID,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        )
        model.id = id
        model.businessID = businessID
        return model
    }
}

struct WorkoutEntryDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var date: Date
    var exercise: String
    var exerciseID: UUID?
    var setEntries: [WorkoutSetEvidence]?
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationMinutes: Int?
    var notes: String
    var mediaAttachments: [MediaAttachmentReference]
    var formScore: Int?
    var intensity: String?
    var feedback: String?
    var estimatedCalories: Int?
    var calorieMET: Double?
    var calorieDurationMinutes: Double?
    var calorieDurationEstimated: Bool
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?
    var sourceWorkoutSessionID: UUID?
    var sourcePerformanceID: UUID?
    var projectionKey: String?

    init(_ model: WorkoutEntry) {
        id = model.id
        businessID = model.businessID
        date = model.date
        exercise = model.exercise
        exerciseID = model.exerciseID
        setEntries = model.setEntries.isEmpty ? nil : model.setEntries
        sets = model.sets
        reps = model.reps
        weight = model.weight
        restSeconds = model.restSeconds
        durationMinutes = model.durationMinutes
        notes = model.notes
        mediaAttachments = model.mediaAttachments
        formScore = model.formScore
        intensity = model.intensity
        feedback = model.feedback
        estimatedCalories = model.estimatedCalories
        calorieMET = model.calorieMET
        calorieDurationMinutes = model.calorieDurationMinutes
        calorieDurationEstimated = model.calorieDurationEstimated
        externalSource = model.externalSource
        externalID = model.externalID
        sourceTurnID = model.sourceTurnID
        sourceSessionID = model.sourceSessionID
        sourceWorkoutSessionID = model.sourceWorkoutSessionID
        sourcePerformanceID = model.sourcePerformanceID
        projectionKey = model.projectionKey
    }

    func makeModel(mediaPathMapping: [String: String]) -> WorkoutEntry {
        let attachments = mapped(mediaAttachments, with: mediaPathMapping)
        let model = WorkoutEntry(
            date: date,
            exercise: exercise,
            exerciseID: exerciseID,
            sets: sets,
            reps: reps,
            weight: weight,
            setEntries: setEntries,
            restSeconds: restSeconds,
            durationMinutes: durationMinutes,
            notes: notes,
            mediaAttachments: attachments,
            formScore: formScore,
            intensity: intensity,
            feedback: feedback,
            estimatedCalories: estimatedCalories,
            calorieMET: calorieMET,
            calorieDurationMinutes: calorieDurationMinutes,
            calorieDurationEstimated: calorieDurationEstimated,
            externalSource: externalSource,
            externalID: externalID,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID,
            sourceWorkoutSessionID: sourceWorkoutSessionID,
            sourcePerformanceID: sourcePerformanceID,
            projectionKey: projectionKey
        )
        model.id = id
        model.businessID = businessID
        if model.projectionKey == nil || model.projectionKey?.isEmpty == true {
            model.projectionKey = SomaDataMigration.entryKey(for: id)
        }
        return model
    }
}

func mapped(
    _ path: String?,
    with mapping: [String: String]
) -> String? {
    path.map { mapping[$0] ?? $0 }
}

func mapped(
    _ attachments: [MediaAttachmentReference],
    with mapping: [String: String]
) -> [MediaAttachmentReference] {
    attachments.map {
        MediaAttachmentReference(
            kind: $0.kind,
            path: mapping[$0.path] ?? $0.path
        )
    }
}
