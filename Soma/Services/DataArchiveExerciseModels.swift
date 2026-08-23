import Foundation

struct ExerciseDefinitionDTO: Codable, Equatable, Sendable {
    var canonicalNameKey: String
    var id: UUID
    var businessID: Int64?
    var canonicalName: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var mergedIntoID: UUID?
    var coachingNotes: String
    var primaryMusclesData: Data
    var secondaryMusclesData: Data
    var movementPatternsData: Data
    var muscleDiagramAssetName: String?
    var userDemoVideos: [MediaAttachmentReference]
    var guidanceVideos: [ExerciseVideoSource]
    var imageReferences: [ExerciseImageReference]?
    var lateralityRaw: String?
    var targetKindRaw: String?

    var referencedMediaPaths: [String] {
        userDemoVideos.map(\.path)
            + guidanceVideos.compactMap(\.localPath)
            + (imageReferences ?? []).compactMap(\.localPath)
    }

    init(_ model: ExerciseDefinition) {
        canonicalNameKey = model.canonicalNameKey
        id = model.id
        businessID = model.businessID
        canonicalName = model.canonicalName
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        archivedAt = model.archivedAt
        mergedIntoID = model.mergedIntoID
        coachingNotes = model.coachingNotes
        primaryMusclesData = model.primaryMusclesData
        secondaryMusclesData = model.secondaryMusclesData
        movementPatternsData = model.movementPatternsData
        muscleDiagramAssetName = model.muscleDiagramAssetName
        userDemoVideos = model.userDemoVideos
        guidanceVideos = model.guidanceVideos
        imageReferences = model.imageReferences
        lateralityRaw = model.lateralityRaw.isEmpty ? nil : model.lateralityRaw
        targetKindRaw = model.targetKindRaw.isEmpty ? nil : model.targetKindRaw
    }

    func makeModel(
        mediaPathMapping: [String: String]
    ) -> ExerciseDefinition {
        let definition = ExerciseDefinition(
            id: id,
            canonicalName: canonicalName,
            createdAt: createdAt,
            coachingNotes: coachingNotes
        )
        definition.canonicalNameKey = canonicalNameKey
        definition.updatedAt = updatedAt
        definition.archivedAt = archivedAt
        definition.mergedIntoID = mergedIntoID
        definition.primaryMusclesData = primaryMusclesData
        definition.secondaryMusclesData = secondaryMusclesData
        definition.movementPatternsData = movementPatternsData
        definition.muscleDiagramAssetName = muscleDiagramAssetName
        definition.userDemoVideos = userDemoVideos.map {
            MediaAttachmentReference(
                kind: $0.kind,
                path: mediaPathMapping[$0.path] ?? $0.path
            )
        }
        definition.guidanceVideos = guidanceVideos.map { source in
            var value = source
            if let path = source.localPath {
                value.localPath = mediaPathMapping[path] ?? path
            }
            return value
        }
        definition.imageReferences = (imageReferences ?? []).map { reference in
            var value = reference
            if let path = reference.localPath {
                value.localPath = mediaPathMapping[path] ?? path
            }
            return value
        }
        definition.businessID = businessID
        if let lateralityRaw {
            definition.lateralityRaw = lateralityRaw
        }
        if let targetKindRaw {
            definition.targetKindRaw = targetKindRaw
        }
        definition.updatedAt = updatedAt
        return definition
    }
}

struct ExerciseMergeRecordDTO: Codable, Equatable, Sendable {
    var id: UUID
    var businessID: Int64?
    var sourceExerciseID: UUID
    var targetExerciseID: UUID
    var sourceName: String
    var affectedWorkoutIDs: [UUID]
    var affectedTemplateExerciseIDs: [UUID]?
    var affectedPerformanceIDs: [UUID]?
    var affectedRecommendationIDs: [UUID]?
    var transferredUserDemoVideos: [MediaAttachmentReference]?
    var transferredGuidanceVideos: [ExerciseVideoSource]?
    var transferredImageReferences: [ExerciseImageReference]?
    var createdAt: Date
    var undoneAt: Date?

    var referencedMediaPaths: [String] {
        (transferredUserDemoVideos ?? []).map(\.path)
            + (transferredGuidanceVideos ?? []).compactMap(\.localPath)
            + (transferredImageReferences ?? []).compactMap(\.localPath)
    }

    init(_ model: ExerciseMergeRecord) {
        id = model.id
        businessID = model.businessID
        sourceExerciseID = model.sourceExerciseID
        targetExerciseID = model.targetExerciseID
        sourceName = model.sourceName
        affectedWorkoutIDs = model.affectedWorkoutIDs
        affectedTemplateExerciseIDs = model.affectedTemplateExerciseIDs
        affectedPerformanceIDs = model.affectedPerformanceIDs
        affectedRecommendationIDs = model.affectedRecommendationIDs
        transferredUserDemoVideos = model.transferredUserDemoVideos
        transferredGuidanceVideos = model.transferredGuidanceVideos
        transferredImageReferences = model.transferredImageReferences
        createdAt = model.createdAt
        undoneAt = model.undoneAt
    }

    func makeModel(
        mediaPathMapping: [String: String]
    ) -> ExerciseMergeRecord {
        let mappedUserDemoVideos = (transferredUserDemoVideos ?? []).map {
            MediaAttachmentReference(
                kind: $0.kind,
                path: mediaPathMapping[$0.path] ?? $0.path
            )
        }
        let mappedGuidanceVideos = (transferredGuidanceVideos ?? []).map { source in
            var value = source
            if let path = source.localPath {
                value.localPath = mediaPathMapping[path] ?? path
            }
            return value
        }
        let mappedImageReferences = (transferredImageReferences ?? []).map { reference in
            var value = reference
            if let path = reference.localPath {
                value.localPath = mediaPathMapping[path] ?? path
            }
            return value
        }
        let record = ExerciseMergeRecord(
            sourceExerciseID: sourceExerciseID,
            targetExerciseID: targetExerciseID,
            sourceName: sourceName,
            affectedWorkoutIDs: affectedWorkoutIDs,
            affectedTemplateExerciseIDs: affectedTemplateExerciseIDs ?? [],
            affectedPerformanceIDs: affectedPerformanceIDs ?? [],
            affectedRecommendationIDs: affectedRecommendationIDs ?? [],
            transferredUserDemoVideos: mappedUserDemoVideos,
            transferredGuidanceVideos: mappedGuidanceVideos,
            transferredImageReferences: mappedImageReferences,
            createdAt: createdAt
        )
        record.id = id
        record.businessID = businessID
        record.undoneAt = undoneAt
        return record
    }
}
