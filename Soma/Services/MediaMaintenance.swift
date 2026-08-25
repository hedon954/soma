import Foundation
import SwiftData

enum MediaReferenceStore {
    static func referencedPaths(in container: ModelContainer) throws -> Set<String> {
        try referencedPaths(in: ModelContext(container))
    }

    static func referencedPaths(in context: ModelContext) throws -> Set<String> {
        var paths = Set<String>()
        func append(_ values: some Sequence<String>) {
            for value in values where !value.isEmpty {
                paths.insert(value)
            }
        }

        try append(context.fetch(FetchDescriptor<GymProfile>()).compactMap(\.coverImagePath))
        try append(context.fetch(FetchDescriptor<GymEquipment>()).compactMap(\.imagePath))
        try append(context.fetch(FetchDescriptor<GymMedia>()).map(\.path))
        try append(
            context.fetch(FetchDescriptor<MealEntry>())
                .flatMap(\.mediaAttachments)
                .map(\.path)
        )
        try append(
            context.fetch(FetchDescriptor<BodyEntry>())
                .flatMap(\.mediaAttachments)
                .map(\.path)
        )
        try append(
            context.fetch(FetchDescriptor<WorkoutEntry>())
                .flatMap(\.mediaAttachments)
                .map(\.path)
        )

        for exercise in try context.fetch(FetchDescriptor<ExerciseDefinition>()) {
            append(exercise.userDemoVideos.map(\.path))
            append(exercise.guidanceVideos.compactMap(\.localPath))
            append(exercise.imageReferences.compactMap(\.localPath))
        }
        for merge in try context.fetch(FetchDescriptor<ExerciseMergeRecord>()) {
            append(merge.transferredUserDemoVideos.map(\.path))
            append(merge.transferredGuidanceVideos.compactMap(\.localPath))
            append(merge.transferredImageReferences.compactMap(\.localPath))
        }

        try append(
            context.fetch(FetchDescriptor<ExercisePerformance>())
                .compactMap(\.activeVideoPath)
        )
        try append(
            context.fetch(FetchDescriptor<WorkoutSet>())
                .compactMap(\.recordedVideoPath)
        )
        try append(
            context.fetch(FetchDescriptor<WorkoutEffort>())
                .compactMap(\.recordedVideoPath)
        )
        try append(
            context.fetch(FetchDescriptor<PerformanceAnalysis>())
                .map(\.sourceMediaPath)
        )
        try append(
            context.fetch(FetchDescriptor<CoachMessage>())
                .flatMap(\.mediaAttachments)
                .map(\.path)
        )
        try append(
            context.fetch(FetchDescriptor<AgentJob>())
                .flatMap(\.mediaAttachments)
                .map(\.path)
        )
        return paths
    }
}

actor MediaMaintenance {
    static let shared = MediaMaintenance()
    static let currentCleanupKey = "media.orphanCleanup.currentBaseline.v2"

    private var isRunning = false

    func reclaimOrphansIfNeeded(
        personalContainer: ModelContainer,
        demoContainer: ModelContainer,
        defaults: UserDefaults = .standard
    ) async {
        guard !isRunning, !defaults.bool(forKey: Self.currentCleanupKey) else { return }
        isRunning = true
        defer { isRunning = false }

        let interval = AppPerformance.begin(
            .rootMaintenance,
            detail: "kind=orphan_media"
        )
        do {
            let retained = try await runDetached {
                try Task.checkCancellation()
                return try MediaReferenceStore.referencedPaths(in: personalContainer)
                    .union(MediaReferenceStore.referencedPaths(in: demoContainer))
            }
            let result = try await runDetached {
                let deduplicated = MediaStore.deduplicateStoredFiles {
                    Task.isCancelled
                }
                try Task.checkCancellation()
                let deleted = MediaStore.removeOrphans(
                    retaining: retained,
                    shouldCancel: { Task.isCancelled }
                )
                try Task.checkCancellation()
                return (deduplicated, deleted)
            }
            defaults.set(true, forKey: Self.currentCleanupKey)
            AppPerformance.end(
                interval,
                detail: "result=success,deduplicated=\(result.0),deleted=\(result.1)"
            )
        } catch {
            AppPerformance.end(interval, detail: "result=failure")
        }
    }

    private func runDetached<T: Sendable>(
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
