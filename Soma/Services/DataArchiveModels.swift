import Foundation
import SwiftData

struct PersonalDataSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var createdAt: Date
    var externalSyncCursors: [ExternalSyncCursorDTO]
    var userProfiles: [UserProfileDTO]
    var gymProfiles: [GymProfileDTO]
    var gymEquipment: [GymEquipmentDTO]
    var gymMedia: [GymMediaDTO]
    var meals: [MealEntryDTO]
    var bodyEntries: [BodyEntryDTO]
    var workouts: [WorkoutEntryDTO]
    var sessions: [ConversationSessionDTO]
    var messages: [CoachMessageDTO]
    var traces: [AgentTraceDTO]
    var mutationReceipts: [AgentMutationReceiptDTO]

    var referencedMediaPaths: Set<String> {
        var paths = Set<String>()
        gymProfiles.compactMap(\.coverImagePath).forEach { paths.insert($0) }
        gymEquipment.compactMap(\.imagePath).forEach { paths.insert($0) }
        gymMedia.map(\.path).forEach { paths.insert($0) }
        meals.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        bodyEntries.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        workouts.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        messages.flatMap(\.mediaAttachments).map(\.path).forEach { paths.insert($0) }
        return paths.filter { !$0.isEmpty }
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DataArchiveError.unsupportedSchema(schemaVersion)
        }
        guard mutationReceipts.allSatisfy(\.hasDecodableResult) else {
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
            workouts: context.fetch(FetchDescriptor<WorkoutEntry>())
                .map(WorkoutEntryDTO.init),
            sessions: context.fetch(FetchDescriptor<ConversationSession>())
                .map(ConversationSessionDTO.init),
            messages: context.fetch(FetchDescriptor<CoachMessage>())
                .map(CoachMessageDTO.init),
            traces: context.fetch(FetchDescriptor<AgentTrace>())
                .map(AgentTraceDTO.init),
            mutationReceipts: context.fetch(FetchDescriptor<AgentMutationReceipt>())
                .map(AgentMutationReceiptDTO.init)
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
            externalSyncCursors.forEach { context.insert($0.makeModel()) }
            userProfiles.forEach { context.insert($0.makeModel()) }
            for gymProfile in gymProfiles {
                context.insert(gymProfile.makeModel(mediaPathMapping: mediaPathMapping))
            }
            for gymEquipment in gymEquipment {
                context.insert(gymEquipment.makeModel(mediaPathMapping: mediaPathMapping))
            }
            for gymMedia in gymMedia {
                context.insert(gymMedia.makeModel(mediaPathMapping: mediaPathMapping))
            }
            for meal in meals {
                context.insert(meal.makeModel(mediaPathMapping: mediaPathMapping))
            }
            for bodyEntry in bodyEntries {
                context.insert(bodyEntry.makeModel(mediaPathMapping: mediaPathMapping))
            }
            for workout in workouts {
                context.insert(workout.makeModel(mediaPathMapping: mediaPathMapping))
            }
            sessions.forEach { context.insert($0.makeModel()) }
            for message in messages {
                context.insert(message.makeModel(mediaPathMapping: mediaPathMapping))
            }
            traces.forEach { context.insert($0.makeModel()) }
            for receipt in mutationReceipts {
                try context.insert(receipt.makeModel())
            }
            try context.save()
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
        model.biologicalSexRaw = biologicalSexRaw
        return model
    }
}

struct GymProfileDTO: Codable, Equatable, Sendable {
    var id: UUID
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
        model.createdAt = createdAt
        return model
    }
}

struct GymEquipmentDTO: Codable, Equatable, Sendable {
    var id: UUID
    var gymID: UUID
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double
    var imagePath: String?
    var createdAt: Date

    init(_ model: GymEquipment) {
        id = model.id
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
    var date: Date
    var mealTypeRaw: String
    var title: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var notes: String
    var mediaAttachments: [MediaAttachmentReference]
    var confidence: Double
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    init(_ model: MealEntry) {
        id = model.id
        date = model.date
        mealTypeRaw = model.mealTypeRaw
        title = model.title
        calories = model.calories
        protein = model.protein
        carbs = model.carbs
        fat = model.fat
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
            notes: notes,
            mediaAttachments: attachments,
            confidence: confidence,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        )
        model.id = id
        model.mealTypeRaw = mealTypeRaw
        return model
    }
}

struct BodyEntryDTO: Codable, Equatable, Sendable {
    var id: UUID
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
        return model
    }
}

struct WorkoutEntryDTO: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var exercise: String
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

    init(_ model: WorkoutEntry) {
        id = model.id
        date = model.date
        exercise = model.exercise
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
    }

    func makeModel(mediaPathMapping: [String: String]) -> WorkoutEntry {
        let attachments = mapped(mediaAttachments, with: mediaPathMapping)
        let model = WorkoutEntry(
            date: date,
            exercise: exercise,
            sets: sets,
            reps: reps,
            weight: weight,
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
            sourceSessionID: sourceSessionID
        )
        model.id = id
        return model
    }
}

private func mapped(
    _ path: String?,
    with mapping: [String: String]
) -> String? {
    path.map { mapping[$0] ?? $0 }
}

private func mapped(
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
