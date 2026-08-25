import Foundation
import HealthKit
import SwiftData

struct HealthKitImportResult: Equatable {
    let workoutCount: Int
    let bodyCount: Int
    let deletedCount: Int

    var summary: String {
        var parts = [
            "新增 \(workoutCount) 条训练",
            "\(bodyCount) 条体重记录"
        ]
        if deletedCount > 0 {
            parts.append("移除 \(deletedCount) 条来源已删除记录")
        }
        return parts.joined(separator: "、")
    }
}

@MainActor
enum HealthKitImporter {
    private struct ChangeBatch {
        let added: [HKSample]
        let deleted: [HKDeletedObject]
        let anchor: HKQueryAnchor?
    }

    private enum Stream {
        static let workouts = "workouts"
        static let bodyMass = "bodyMass"
    }

    private static let sourceID = "healthkit"
    private static let sourceName = "Apple 健康"
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestAuthorizationAndImport(
        into context: ModelContext
    ) async throws -> HealthKitImportResult {
        guard isAvailable else {
            throw HealthKitImportError.unavailable
        }
        guard
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            throw HealthKitImportError.typesUnavailable
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            bodyMass,
            activeEnergy
        ]
        try await store.requestAuthorization(toShare: [], read: readTypes)

        let workoutCursor = syncCursor(for: Stream.workouts, in: context)
        let bodyCursor = syncCursor(for: Stream.bodyMass, in: context)
        async let workoutChanges = changes(
            of: HKObjectType.workoutType(),
            after: decodeAnchor(workoutCursor?.cursorData)
        )
        async let bodyChanges = changes(
            of: bodyMass,
            after: decodeAnchor(bodyCursor?.cursorData)
        )
        let (resolvedWorkoutChanges, resolvedBodyChanges) = try await (
            workoutChanges,
            bodyChanges
        )

        return try importSamples(
            workoutChanges: resolvedWorkoutChanges,
            bodyChanges: resolvedBodyChanges,
            activeEnergyType: activeEnergy,
            workoutCursor: workoutCursor,
            bodyCursor: bodyCursor,
            into: context
        )
    }

    private static var oneYearAgo: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
    }

    private static func changes(
        of type: HKSampleType,
        after anchor: HKQueryAnchor?
    ) async throws -> ChangeBatch {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: oneYearAgo,
                end: .now,
                options: .strictStartDate
            )
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ChangeBatch(
                        added: samples ?? [],
                        deleted: deletedObjects ?? [],
                        anchor: newAnchor
                    ))
                }
            }
            store.execute(query)
        }
    }

    private static func importSamples(
        workoutChanges: ChangeBatch,
        bodyChanges: ChangeBatch,
        activeEnergyType: HKQuantityType,
        workoutCursor: ExternalSyncCursor?,
        bodyCursor: ExternalSyncCursor?,
        into context: ModelContext
    ) throws -> HealthKitImportResult {
        let deletedWorkoutIDs = Set(workoutChanges.deleted.map(\.uuid.uuidString))
        let deletedBodyIDs = Set(bodyChanges.deleted.map(\.uuid.uuidString))
        var insertedWorkoutIDs: Set<String> = []
        var insertedBodyIDs: Set<String> = []
        var workoutCount = 0
        var bodyCount = 0

        for workout in workoutChanges.added.compactMap({ $0 as? HKWorkout }) {
            let externalID = workout.uuid.uuidString
            guard
                !deletedWorkoutIDs.contains(externalID),
                insertedWorkoutIDs.insert(externalID).inserted,
                !containsWorkout(
                    externalID: externalID,
                    source: sourceName,
                    in: context
                )
            else { continue }
            let energy = workout
                .statistics(for: activeEnergyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            context.insert(WorkoutEntry(
                date: workout.startDate,
                exercise: workoutTitle(workout.workoutActivityType),
                durationMinutes: max(Int((workout.duration / 60).rounded()), 1),
                notes: "从 Apple 健康导入",
                estimatedCalories: energy.map { Int($0.rounded()) },
                calorieDurationMinutes: workout.duration / 60,
                calorieDurationEstimated: false,
                externalSource: sourceName,
                externalID: externalID
            ))
            workoutCount += 1
        }

        for sample in bodyChanges.added.compactMap({ $0 as? HKQuantitySample }) {
            let externalID = sample.uuid.uuidString
            guard
                !deletedBodyIDs.contains(externalID),
                insertedBodyIDs.insert(externalID).inserted,
                !containsBodyEntry(
                    externalID: externalID,
                    source: sourceName,
                    in: context
                )
            else { continue }
            let weight = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard weight > 0 else { continue }
            context.insert(BodyEntry(
                date: sample.startDate,
                weight: weight,
                notes: "从 Apple 健康导入",
                analysis: "",
                externalSource: sourceName,
                externalID: externalID
            ))
            bodyCount += 1
        }

        var deletedCount = 0

        for externalID in deletedWorkoutIDs {
            for workout in workouts(
                externalID: externalID,
                source: sourceName,
                in: context
            ) {
                context.delete(workout)
                deletedCount += 1
            }
        }
        for externalID in deletedBodyIDs {
            for bodyEntry in bodyEntries(
                externalID: externalID,
                source: sourceName,
                in: context
            ) {
                context.delete(bodyEntry)
                deletedCount += 1
            }
        }

        try updateCursor(
            workoutCursor,
            stream: Stream.workouts,
            anchor: workoutChanges.anchor,
            in: context
        )
        try updateCursor(
            bodyCursor,
            stream: Stream.bodyMass,
            anchor: bodyChanges.anchor,
            in: context
        )
        try context.save()
        return HealthKitImportResult(
            workoutCount: workoutCount,
            bodyCount: bodyCount,
            deletedCount: deletedCount
        )
    }

    private static func containsWorkout(
        externalID: String,
        source: String,
        in context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate {
                $0.externalSource == source && $0.externalID == externalID
            }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private static func containsBodyEntry(
        externalID: String,
        source: String,
        in context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate {
                $0.externalSource == source && $0.externalID == externalID
            }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private static func workouts(
        externalID: String,
        source: String,
        in context: ModelContext
    ) -> [WorkoutEntry] {
        (try? context.fetch(FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate {
                $0.externalSource == source && $0.externalID == externalID
            }
        ))) ?? []
    }

    private static func bodyEntries(
        externalID: String,
        source: String,
        in context: ModelContext
    ) -> [BodyEntry] {
        (try? context.fetch(FetchDescriptor<BodyEntry>(
            predicate: #Predicate {
                $0.externalSource == source && $0.externalID == externalID
            }
        ))) ?? []
    }

    private static func syncCursor(
        for stream: String,
        in context: ModelContext
    ) -> ExternalSyncCursor? {
        let descriptor = FetchDescriptor<ExternalSyncCursor>(
            predicate: #Predicate {
                $0.source == sourceID && $0.stream == stream
            }
        )
        return try? context.fetch(descriptor).first
    }

    private static func decodeAnchor(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: data
        )
    }

    private static func updateCursor(
        _ existingCursor: ExternalSyncCursor?,
        stream: String,
        anchor: HKQueryAnchor?,
        in context: ModelContext
    ) throws {
        guard let anchor else { return }
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )
        if let existingCursor {
            existingCursor.cursorData = data
            existingCursor.updatedAt = .now
        } else {
            context.insert(ExternalSyncCursor(
                source: sourceID,
                stream: stream,
                cursorData: data
            ))
        }
    }

    private static func workoutTitle(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .traditionalStrengthTraining: "力量训练"
        case .functionalStrengthTraining: "功能性力量训练"
        case .highIntensityIntervalTraining: "高强度间歇训练"
        case .running: "跑步"
        case .walking: "步行"
        case .cycling: "骑行"
        case .swimming: "游泳"
        case .hiking: "徒步"
        case .yoga: "瑜伽"
        case .coreTraining: "核心训练"
        case .crossTraining: "交叉训练"
        case .stairClimbing: "爬楼训练"
        default: "Apple 健康训练"
        }
    }
}

enum HealthKitImportError: LocalizedError {
    case unavailable
    case typesUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前设备不支持 Apple 健康数据"
        case .typesUnavailable:
            "系统没有提供所需的健康数据类型"
        }
    }
}
