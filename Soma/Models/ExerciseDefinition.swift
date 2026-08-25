import Foundation
import SwiftData

struct ExerciseVideoSource: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum SourceKind: String, Codable, Sendable {
        case soma
        case authorized
        case externalLink
    }

    var id: UUID
    var title: String
    var kind: SourceKind
    var url: URL?
    var localPath: String?

    init(
        id: UUID = UUID(),
        title: String,
        kind: SourceKind,
        url: URL? = nil,
        localPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.url = url
        self.localPath = localPath
    }
}

struct ExerciseContent: Codable, Equatable, Sendable {
    var coachingNotes: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var movementPatterns: [String]
}

enum ExerciseImageKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case actionIllustration
    case muscleMap

    var id: String {
        rawValue
    }
}

enum ExerciseImageSource: String, Codable, Hashable, Sendable {
    case bundled
    case generated
    case user
}

struct ExerciseImageReference: Codable, Equatable, Hashable, Identifiable, Sendable {
    var kind: ExerciseImageKind
    var source: ExerciseImageSource
    var title: String
    var resourceName: String?
    var localPath: String?
    var createdAt: Date

    init(
        kind: ExerciseImageKind,
        source: ExerciseImageSource,
        title: String,
        resourceName: String? = nil,
        localPath: String? = nil,
        createdAt: Date = .now
    ) {
        self.kind = kind
        self.source = source
        self.title = title
        self.resourceName = resourceName
        self.localPath = localPath
        self.createdAt = createdAt
    }

    var id: String {
        [
            kind.rawValue,
            source.rawValue,
            resourceName ?? "",
            localPath ?? ""
        ].joined(separator: ":")
    }
}

private enum ExerciseDefinitionCoding {
    static func encode(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Model
final class ExerciseDefinition: BusinessIdentifiedModel {
    @Attribute(.unique) var canonicalNameKey: String
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
    var userDemoVideosData: Data
    var guidanceVideosData: Data
    var imageReferencesData: Data = Data()
    var lateralityRaw: String = ""
    var targetKindRaw: String = ""

    init(
        id: UUID = UUID(),
        canonicalName: String,
        createdAt: Date = .now,
        coachingNotes: String = "",
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        movementPatterns: [String] = []
    ) {
        self.id = id
        self.canonicalName = canonicalName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        canonicalNameKey = ExerciseLibraryStore.canonicalNameKey(canonicalName)
        self.createdAt = createdAt
        updatedAt = createdAt
        self.coachingNotes = coachingNotes
        primaryMusclesData = ExerciseDefinitionCoding.encode(primaryMuscles)
        secondaryMusclesData = ExerciseDefinitionCoding.encode(secondaryMuscles)
        movementPatternsData = ExerciseDefinitionCoding.encode(movementPatterns)
        userDemoVideosData = ExerciseDefinitionCoding.encode(
            [MediaAttachmentReference]()
        )
        guidanceVideosData = ExerciseDefinitionCoding.encode(
            [ExerciseVideoSource]()
        )
        imageReferencesData = ExerciseDefinitionCoding.encode(
            [ExerciseImageReference]()
        )
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var primaryMuscles: [String] {
        get {
            ExerciseDefinitionCoding.decode(
                [String].self,
                from: primaryMusclesData
            ) ?? []
        }
        set {
            primaryMusclesData = ExerciseDefinitionCoding.encode(newValue)
            updatedAt = .now
        }
    }

    var secondaryMuscles: [String] {
        get {
            ExerciseDefinitionCoding.decode(
                [String].self,
                from: secondaryMusclesData
            ) ?? []
        }
        set {
            secondaryMusclesData = ExerciseDefinitionCoding.encode(newValue)
            updatedAt = .now
        }
    }

    var movementPatterns: [String] {
        get {
            ExerciseDefinitionCoding.decode(
                [String].self,
                from: movementPatternsData
            ) ?? []
        }
        set {
            movementPatternsData = ExerciseDefinitionCoding.encode(newValue)
            updatedAt = .now
        }
    }

    var userDemoVideos: [MediaAttachmentReference] {
        get {
            ExerciseDefinitionCoding.decode(
                [MediaAttachmentReference].self,
                from: userDemoVideosData
            ) ?? []
        }
        set {
            userDemoVideosData = ExerciseDefinitionCoding.encode(newValue)
            updatedAt = .now
        }
    }

    var guidanceVideos: [ExerciseVideoSource] {
        get {
            ExerciseDefinitionCoding.decode(
                [ExerciseVideoSource].self,
                from: guidanceVideosData
            ) ?? []
        }
        set {
            guidanceVideosData = ExerciseDefinitionCoding.encode(newValue)
            updatedAt = .now
        }
    }

    var imageReferences: [ExerciseImageReference] {
        get {
            ExerciseDefinitionCoding.decode(
                [ExerciseImageReference].self,
                from: imageReferencesData
            ) ?? []
        }
        set {
            imageReferencesData = ExerciseDefinitionCoding.encode(newValue)
            updatedAt = .now
        }
    }

    var hasExplicitLaterality: Bool {
        ExerciseLaterality(rawValue: lateralityRaw) != nil
    }

    var laterality: ExerciseLaterality {
        get { ExerciseLaterality(rawValue: lateralityRaw) ?? .none }
        set {
            lateralityRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var hasExplicitTargetKind: Bool {
        WorkoutTargetKind(rawValue: targetKindRaw) != nil
    }

    var targetKind: WorkoutTargetKind {
        get { WorkoutTargetKind(rawValue: targetKindRaw) ?? .repetitions }
        set {
            targetKindRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var actionIllustrations: [ExerciseImageReference] {
        imageReferences
            .filter { $0.kind == .actionIllustration }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var muscleMaps: [ExerciseImageReference] {
        imageReferences
            .filter { $0.kind == .muscleMap }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func apply(_ content: ExerciseContent) {
        coachingNotes = content.coachingNotes
        primaryMuscles = content.primaryMuscles
        secondaryMuscles = content.secondaryMuscles
        movementPatterns = content.movementPatterns
        updatedAt = .now
    }
}

@Model
final class ExerciseMergeRecord: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var sourceExerciseID: UUID
    var targetExerciseID: UUID
    var sourceName: String
    var affectedWorkoutIDsData: Data
    var affectedTemplateExerciseIDsData: Data = Data()
    var affectedPerformanceIDsData: Data = Data()
    var affectedRecommendationIDsData: Data = Data()
    var transferredUserDemoVideosData: Data = Data()
    var transferredGuidanceVideosData: Data = Data()
    var transferredImageReferencesData: Data = Data()
    var createdAt: Date
    var undoneAt: Date?

    init(
        sourceExerciseID: UUID,
        targetExerciseID: UUID,
        sourceName: String,
        affectedWorkoutIDs: [UUID],
        affectedTemplateExerciseIDs: [UUID] = [],
        affectedPerformanceIDs: [UUID] = [],
        affectedRecommendationIDs: [UUID] = [],
        transferredUserDemoVideos: [MediaAttachmentReference] = [],
        transferredGuidanceVideos: [ExerciseVideoSource] = [],
        transferredImageReferences: [ExerciseImageReference] = [],
        createdAt: Date = .now
    ) {
        id = UUID()
        self.sourceExerciseID = sourceExerciseID
        self.targetExerciseID = targetExerciseID
        self.sourceName = sourceName
        affectedWorkoutIDsData = ExerciseDefinitionCoding.encode(
            affectedWorkoutIDs
        )
        affectedTemplateExerciseIDsData = ExerciseDefinitionCoding.encode(
            affectedTemplateExerciseIDs
        )
        affectedPerformanceIDsData = ExerciseDefinitionCoding.encode(
            affectedPerformanceIDs
        )
        affectedRecommendationIDsData = ExerciseDefinitionCoding.encode(
            affectedRecommendationIDs
        )
        transferredUserDemoVideosData = ExerciseDefinitionCoding.encode(
            transferredUserDemoVideos
        )
        transferredGuidanceVideosData = ExerciseDefinitionCoding.encode(
            transferredGuidanceVideos
        )
        transferredImageReferencesData = ExerciseDefinitionCoding.encode(
            transferredImageReferences
        )
        self.createdAt = createdAt
    }

    var affectedWorkoutIDs: [UUID] {
        ExerciseDefinitionCoding.decode(
            [UUID].self,
            from: affectedWorkoutIDsData
        ) ?? []
    }

    var affectedTemplateExerciseIDs: [UUID] {
        ExerciseDefinitionCoding.decode(
            [UUID].self,
            from: affectedTemplateExerciseIDsData
        ) ?? []
    }

    var affectedPerformanceIDs: [UUID] {
        ExerciseDefinitionCoding.decode(
            [UUID].self,
            from: affectedPerformanceIDsData
        ) ?? []
    }

    var affectedRecommendationIDs: [UUID] {
        ExerciseDefinitionCoding.decode(
            [UUID].self,
            from: affectedRecommendationIDsData
        ) ?? []
    }

    var transferredUserDemoVideos: [MediaAttachmentReference] {
        ExerciseDefinitionCoding.decode(
            [MediaAttachmentReference].self,
            from: transferredUserDemoVideosData
        ) ?? []
    }

    var transferredGuidanceVideos: [ExerciseVideoSource] {
        ExerciseDefinitionCoding.decode(
            [ExerciseVideoSource].self,
            from: transferredGuidanceVideosData
        ) ?? []
    }

    var transferredImageReferences: [ExerciseImageReference] {
        ExerciseDefinitionCoding.decode(
            [ExerciseImageReference].self,
            from: transferredImageReferencesData
        ) ?? []
    }
}

struct ExerciseNameReference: Codable, Equatable, Identifiable, Sendable {
    var id: Int64
    var name: String
}

enum ExerciseQuickFill {
    static func text(for workout: WorkoutEntry) -> String {
        WorkoutHistoryFormatter.text(for: workout)
    }

    static func text(for sets: [WorkoutSet]) -> String {
        WorkoutHistoryFormatter.text(for: sets)
    }
}

enum ExerciseLibraryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case missingExercise(UUID)
    case archivedExercise(UUID)
    case ambiguousReference
    case invalidReference
    case invalidMerge
    case mergeNotUndoable

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "动作名称不能为空。"
        case let .duplicateName(name):
            "动作库中已存在“\(name)”。"
        case let .missingExercise(id):
            "动作 ID \(id.uuidString) 已失效，请重新读取动作列表。"
        case let .archivedExercise(id):
            "动作 ID \(id.uuidString) 已归档，请重新读取动作列表。"
        case .ambiguousReference:
            "exercise_id 与 exercise_name 只能提供一个，请重新读取动作列表后选择。"
        case .invalidReference:
            "exercise_id 不是有效 UUID，请重新读取动作列表。"
        case .invalidMerge:
            "不能把动作合并到自身或已归档动作。"
        case .mergeNotUndoable:
            "没有可以安全撤销的动作合并。"
        }
    }
}

@MainActor
enum ExerciseLibraryStore {
    nonisolated static func canonicalNameKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func activeDefinitions(in context: ModelContext) -> [ExerciseDefinition] {
        (
            try? context.fetch(
                FetchDescriptor<ExerciseDefinition>(
                    predicate: #Predicate { $0.archivedAt == nil },
                    sortBy: [SortDescriptor(\.canonicalName)]
                )
            )
        ) ?? []
    }

    static func nameReferences(in context: ModelContext) -> [ExerciseNameReference] {
        activeDefinitions(in: context).map {
            ExerciseNameReference(id: $0.businessID ?? 0, name: $0.canonicalName)
        }
    }

    static func definition(
        id: UUID,
        in context: ModelContext
    ) throws -> ExerciseDefinition {
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let value = (try? context.fetch(descriptor))?.first else {
            throw ExerciseLibraryError.missingExercise(id)
        }
        guard !value.isArchived else {
            throw ExerciseLibraryError.archivedExercise(id)
        }
        return value
    }

    static func definition(
        businessID: Int64,
        in context: ModelContext
    ) throws -> ExerciseDefinition {
        guard businessID > 0 else {
            throw ExerciseLibraryError.invalidReference
        }
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate {
                $0.businessID == businessID && $0.archivedAt == nil
            }
        )
        descriptor.fetchLimit = 1
        guard let value = (try? context.fetch(descriptor))?.first else {
            throw ExerciseLibraryError.invalidReference
        }
        return value
    }

    static func resolveOrCreateExact(
        canonicalName: String,
        in context: ModelContext
    ) throws -> ExerciseDefinition {
        let name = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = canonicalNameKey(name)
        guard !key.isEmpty else { throw ExerciseLibraryError.emptyName }
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate {
                $0.canonicalNameKey == key && $0.archivedAt == nil
            }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            try BusinessIDAllocator.assign(
                existing,
                namespace: "exercise",
                in: context
            )
            if BundledExerciseCatalog.activateIfAvailable(existing) {
                try context.save()
            }
            return existing
        }
        let value = ExerciseDefinition(canonicalName: name)
        _ = BundledExerciseCatalog.activateIfAvailable(value)
        context.insert(value)
        try BusinessIDAllocator.assign(
            value,
            namespace: "exercise",
            in: context
        )
        try context.save()
        return value
    }

    static func rename(
        _ exercise: ExerciseDefinition,
        to name: String,
        in context: ModelContext
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = canonicalNameKey(trimmed)
        guard !key.isEmpty else { throw ExerciseLibraryError.emptyName }
        let exerciseID = exercise.id
        var duplicateDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate {
                $0.id != exerciseID
                    && $0.canonicalNameKey == key
                    && $0.archivedAt == nil
            }
        )
        duplicateDescriptor.fetchLimit = 1
        guard (try? context.fetch(duplicateDescriptor))?.isEmpty != false else {
            throw ExerciseLibraryError.duplicateName(trimmed)
        }
        exercise.canonicalName = trimmed
        exercise.canonicalNameKey = key
        _ = BundledExerciseCatalog.activateIfAvailable(exercise)
        exercise.updatedAt = .now
        let workouts = (
            try? context.fetch(FetchDescriptor<WorkoutEntry>(
                predicate: #Predicate { $0.exerciseID == exerciseID }
            ))
        ) ?? []
        for workout in workouts {
            workout.exercise = trimmed
        }
        try context.save()
    }

    static func archive(
        _ exercise: ExerciseDefinition,
        in context: ModelContext
    ) throws {
        exercise.archivedAt = .now
        exercise.updatedAt = .now
        try context.save()
    }

    static func merge(
        source: ExerciseDefinition,
        into target: ExerciseDefinition,
        in context: ModelContext
    ) throws -> ExerciseMergeRecord {
        guard source.id != target.id,
              !source.isArchived,
              !target.isArchived
        else {
            throw ExerciseLibraryError.invalidMerge
        }
        let sourceID = source.id
        let affected = (
            try? context.fetch(FetchDescriptor<WorkoutEntry>(
                predicate: #Predicate { $0.exerciseID == sourceID }
            ))
        ) ?? []
        for workout in affected {
            workout.exerciseID = target.id
            workout.exerciseDefinition = target
            workout.exercise = target.canonicalName
        }
        let affectedTemplateExercises = (
            try? context.fetch(FetchDescriptor<TemplateExercise>(
                predicate: #Predicate { $0.exerciseID == sourceID }
            ))
        ) ?? []
        for templateExercise in affectedTemplateExercises {
            templateExercise.exerciseID = target.id
            templateExercise.exerciseDefinition = target
        }
        let affectedPerformances = (
            try? context.fetch(FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.exerciseID == sourceID }
            ))
        ) ?? []
        for performance in affectedPerformances {
            performance.exerciseID = target.id
            performance.exerciseDefinition = target
            performance.exerciseName = target.canonicalName
            if var prescription = performance.prescriptionSnapshot {
                prescription.exerciseID = target.id
                prescription.exerciseName = target.canonicalName
                performance.prescriptionSnapshotData = TrainingPlanCoding.encode(
                    prescription
                )
            }
        }
        let affectedRecommendations = (
            try? context.fetch(FetchDescriptor<RecommendationSnapshot>(
                predicate: #Predicate {
                    $0.targetKind == "exercise" && $0.targetID == sourceID
                }
            ))
        ) ?? []
        for recommendation in affectedRecommendations {
            recommendation.targetID = target.id
        }
        let targetUserVideoIDs = Set(target.userDemoVideos.map(\.id))
        let transferredUserVideos = source.userDemoVideos.filter {
            !targetUserVideoIDs.contains($0.id)
        }
        let targetGuidanceVideoIDs = Set(target.guidanceVideos.map(\.id))
        let transferredGuidanceVideos = source.guidanceVideos.filter {
            !targetGuidanceVideoIDs.contains($0.id)
        }
        let targetImageIDs = Set(target.imageReferences.map(\.id))
        let transferredImageReferences = source.imageReferences.filter {
            !targetImageIDs.contains($0.id)
        }
        target.userDemoVideos += transferredUserVideos
        target.guidanceVideos += transferredGuidanceVideos
        target.imageReferences += transferredImageReferences
        let transferredUserIDs = Set(transferredUserVideos.map(\.id))
        let transferredGuidanceIDs = Set(transferredGuidanceVideos.map(\.id))
        let transferredImageIDs = Set(transferredImageReferences.map(\.id))
        source.userDemoVideos.removeAll {
            transferredUserIDs.contains($0.id)
        }
        source.guidanceVideos.removeAll {
            transferredGuidanceIDs.contains($0.id)
        }
        source.imageReferences.removeAll {
            transferredImageIDs.contains($0.id)
        }
        source.archivedAt = .now
        source.mergedIntoID = target.id
        source.updatedAt = .now
        let record = ExerciseMergeRecord(
            sourceExerciseID: source.id,
            targetExerciseID: target.id,
            sourceName: source.canonicalName,
            affectedWorkoutIDs: affected.map(\.id),
            affectedTemplateExerciseIDs: affectedTemplateExercises.map(\.id),
            affectedPerformanceIDs: affectedPerformances.map(\.id),
            affectedRecommendationIDs: affectedRecommendations.map(\.id),
            transferredUserDemoVideos: transferredUserVideos,
            transferredGuidanceVideos: transferredGuidanceVideos,
            transferredImageReferences: transferredImageReferences
        )
        context.insert(record)
        try context.save()
        return record
    }

    static func undo(
        _ record: ExerciseMergeRecord,
        in context: ModelContext
    ) throws {
        guard record.undoneAt == nil else {
            throw ExerciseLibraryError.mergeNotUndoable
        }
        let sourceID = record.sourceExerciseID
        let targetID = record.targetExerciseID
        var sourceDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.id == sourceID }
        )
        sourceDescriptor.fetchLimit = 1
        var targetDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.id == targetID }
        )
        targetDescriptor.fetchLimit = 1
        guard let source = (try? context.fetch(sourceDescriptor))?.first,
              let target = (try? context.fetch(targetDescriptor))?.first,
              source.mergedIntoID == record.targetExerciseID
        else {
            throw ExerciseLibraryError.mergeNotUndoable
        }
        let transferredUserIDs = Set(record.transferredUserDemoVideos.map(\.id))
        let transferredGuidanceIDs = Set(
            record.transferredGuidanceVideos.map(\.id)
        )
        let transferredImageIDs = Set(
            record.transferredImageReferences.map(\.id)
        )
        guard transferredUserIDs.isSubset(of: Set(target.userDemoVideos.map(\.id))),
              transferredGuidanceIDs.isSubset(
                  of: Set(target.guidanceVideos.map(\.id))
              ),
              transferredImageIDs.isSubset(
                  of: Set(target.imageReferences.map(\.id))
              )
        else {
            throw ExerciseLibraryError.mergeNotUndoable
        }
        let affectedIDs = Set(record.affectedWorkoutIDs)
        let targetWorkouts = (
            try? context.fetch(FetchDescriptor<WorkoutEntry>(
                predicate: #Predicate { $0.exerciseID == targetID }
            ))
        ) ?? []
        for workout in targetWorkouts
            where affectedIDs.contains(workout.id)
            && workout.exerciseID == record.targetExerciseID
        {
            workout.exerciseID = source.id
            workout.exerciseDefinition = source
            workout.exercise = source.canonicalName
        }
        let affectedTemplateIDs = Set(record.affectedTemplateExerciseIDs)
        for templateExercise in (
            try? context.fetch(FetchDescriptor<TemplateExercise>(
                predicate: #Predicate { $0.exerciseID == targetID }
            ))
        ) ?? [] where affectedTemplateIDs.contains(templateExercise.id)
            && templateExercise.exerciseID == target.id
        {
            templateExercise.exerciseID = source.id
            templateExercise.exerciseDefinition = source
        }
        let affectedPerformanceIDs = Set(record.affectedPerformanceIDs)
        for performance in (
            try? context.fetch(FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.exerciseID == targetID }
            ))
        ) ?? [] where affectedPerformanceIDs.contains(performance.id)
            && performance.exerciseID == target.id
        {
            performance.exerciseID = source.id
            performance.exerciseDefinition = source
            performance.exerciseName = source.canonicalName
            if var prescription = performance.prescriptionSnapshot {
                prescription.exerciseID = source.id
                prescription.exerciseName = source.canonicalName
                performance.prescriptionSnapshotData = TrainingPlanCoding.encode(
                    prescription
                )
            }
        }
        let affectedRecommendationIDs = Set(record.affectedRecommendationIDs)
        for recommendation in (
            try? context.fetch(FetchDescriptor<RecommendationSnapshot>(
                predicate: #Predicate {
                    $0.targetKind == "exercise" && $0.targetID == targetID
                }
            ))
        ) ?? [] where affectedRecommendationIDs.contains(recommendation.id)
            && recommendation.targetKind == "exercise"
            && recommendation.targetID == target.id
        {
            recommendation.targetID = source.id
        }
        target.userDemoVideos.removeAll {
            transferredUserIDs.contains($0.id)
        }
        target.guidanceVideos.removeAll {
            transferredGuidanceIDs.contains($0.id)
        }
        target.imageReferences.removeAll {
            transferredImageIDs.contains($0.id)
        }
        source.userDemoVideos += record.transferredUserDemoVideos
        source.guidanceVideos += record.transferredGuidanceVideos
        source.imageReferences += record.transferredImageReferences
        source.archivedAt = nil
        source.mergedIntoID = nil
        source.updatedAt = .now
        record.undoneAt = .now
        try context.save()
    }

    static func migrateLegacyWorkoutNames(in context: ModelContext) {
        let workouts = fetchWorkouts(in: context)
        let unresolved = workouts.filter {
            $0.exerciseID == nil
                && !canonicalNameKey($0.exercise).isEmpty
        }
        guard !unresolved.isEmpty else { return }
        for group in Dictionary(grouping: unresolved, by: {
            canonicalNameKey($0.exercise)
        }).values {
            guard let name = group.first?.exercise else { continue }
            guard let definition = try? resolveOrCreateExact(
                canonicalName: name,
                in: context
            ) else {
                continue
            }
            for workout in group {
                workout.exerciseID = definition.id
                workout.exerciseDefinition = definition
                workout.exercise = definition.canonicalName
            }
        }
        try? context.save()
    }

    /// Resolves the exercise metadata linked to a workout record.
    /// When `persist` is true and the workout only has a name, writes `exerciseID`
    /// (and canonical name) so subsequent queries and UI stay attached.
    @discardableResult
    static func linkedExercise(
        for workout: WorkoutEntry,
        in context: ModelContext,
        persist: Bool = true,
        allowCreate: Bool = false
    ) throws -> ExerciseDefinition? {
        if let related = workout.exerciseDefinition,
           related.id == workout.exerciseID,
           related.mergedIntoID == nil
        {
            return related
        }
        if let exerciseID = workout.exerciseID {
            var linkedDescriptor = FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate {
                    $0.id == exerciseID && $0.mergedIntoID == nil
                }
            )
            linkedDescriptor.fetchLimit = 1
            if let linked = (try? context.fetch(linkedDescriptor))?.first {
                if persist, workout.exerciseDefinition?.id != linked.id {
                    workout.exerciseDefinition = linked
                    try? context.save()
                }
                return linked
            }
        }

        let name = workout.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let definition: ExerciseDefinition?
        if allowCreate {
            definition = try resolveOrCreateExact(canonicalName: name, in: context)
        } else {
            let key = canonicalNameKey(name)
            var nameDescriptor = FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate {
                    $0.canonicalNameKey == key && $0.archivedAt == nil
                }
            )
            nameDescriptor.fetchLimit = 1
            definition = (try? context.fetch(nameDescriptor))?.first
        }
        guard let definition else { return nil }

        if persist,
           workout.exerciseID != definition.id
           || workout.exerciseDefinition?.id != definition.id
           || workout.exercise != definition.canonicalName
        {
            workout.exerciseID = definition.id
            workout.exerciseDefinition = definition
            workout.exercise = definition.canonicalName
            try? context.save()
        }
        return definition
    }

    /// Backfills `exerciseID` for a page of history rows without creating new exercises.
    static func linkExistingExercises(
        for workouts: [WorkoutEntry],
        in context: ModelContext
    ) {
        var changed = false
        for workout in workouts where workout.exerciseID == nil {
            if let linked = try? linkedExercise(
                for: workout,
                in: context,
                persist: false,
                allowCreate: false
            ) {
                workout.exerciseID = linked.id
                workout.exerciseDefinition = linked
                workout.exercise = linked.canonicalName
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }

    static func activateBundledContent(in context: ModelContext) {
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        var changed = false
        for definition in definitions {
            let activated = BundledExerciseCatalog.activateIfAvailable(definition)
            changed = activated || changed
        }
        if changed {
            try? context.save()
        }
    }

    private static func fetchWorkouts(in context: ModelContext) -> [WorkoutEntry] {
        (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
    }
}
