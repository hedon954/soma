import CryptoKit
import Foundation
import SwiftData

private struct GeneratedExerciseContent: Decodable {
    var coachingNotes: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var movementPatterns: [String]
}

private final class PerformanceFingerprintCache {
    static let shared = PerformanceFingerprintCache()

    private let values = NSCache<NSString, NSString>()

    private init() {
        values.countLimit = 32
    }

    func value(for key: String) -> String? {
        values.object(forKey: key as NSString) as String?
    }

    func insert(_ value: String, for key: String) {
        values.setObject(value as NSString, forKey: key as NSString)
    }

    func removeAll() {
        values.removeAllObjects()
    }
}

@MainActor
enum TrainingIntelligenceService {
    static func optimize(
        program: TrainingProgram,
        prescriptions: [TemplateExercisePrescription],
        ai: AIService,
        in context: ModelContext
    ) async throws -> RecommendationSnapshot {
        let exerciseIDs = Set(prescriptions.map(\.exerciseID))
        let relevant = exerciseIDs.flatMap { exerciseID in
            var descriptor = FetchDescriptor<WorkoutEntry>(
                predicate: #Predicate { $0.exerciseID == exerciseID },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 30
            return (try? context.fetch(descriptor)) ?? []
        }
        .sorted { $0.date > $1.date }
        let fingerprint = planFingerprint(
            prescriptions: prescriptions,
            workouts: Array(relevant.prefix(30))
        )
        let programID = program.id
        let targetKind = "training_program"
        var recommendationDescriptor = FetchDescriptor<RecommendationSnapshot>(
            predicate: #Predicate {
                $0.targetKind == targetKind
                    && $0.targetID == programID
                    && $0.inputFingerprint == fingerprint
            }
        )
        recommendationDescriptor.fetchLimit = 1
        let existing = try? context.fetch(recommendationDescriptor).first
        if let existing {
            return existing
        }
        let prescriptionText = prescriptions
            .sorted { $0.order < $1.order }
            .map { item in
                [
                    "\(item.order). \(item.exerciseName)",
                    WorkoutPrescriptionFormatter.exerciseSummary(item)
                ].joined(separator: " · ")
            }
            .joined(separator: "\n")
        let historyText = relevant.prefix(30).map {
            "\($0.date.formatted(date: .numeric, time: .omitted)) · \($0.exercise) · \(ExerciseQuickFill.text(for: $0))"
        }.joined(separator: "\n")
        let prompt = SomaPrompt.text("training_optimization_user_prompt", [
            "program_name": program.name,
            "prescription": prescriptionText,
            "history": historyText.isEmpty ? "暂无" : historyText
        ])
        let advice = try await ai.completeTextPrompt(
            system: SomaPrompt.text("training_optimization_system_prompt"),
            user: prompt,
            reason: "训练课程优化",
            tier: .standard,
            recoverFinalAnswer: true
        )
        let snapshot = RecommendationSnapshot(
            targetKind: "training_program",
            targetID: program.id,
            inputFingerprint: fingerprint,
            advice: advice
        )
        context.insert(snapshot)
        try context.save()
        return snapshot
    }

    static func generateContent(
        for exercise: ExerciseDefinition,
        ai: AIService,
        in context: ModelContext
    ) async throws -> ExerciseContent {
        let prompt = SomaPrompt.text("exercise_content_user_prompt", ["exercise_name": exercise.canonicalName])
        let answer = try await ai.completeTextPrompt(
            system: SomaPrompt.text("exercise_content_system_prompt"),
            user: prompt,
            reason: "动作说明生成",
            tier: .standard,
            recoverFinalAnswer: true
        )
        let generated = try decodeJSON(
            GeneratedExerciseContent.self,
            from: answer
        )
        let content = ExerciseContent(
            coachingNotes: generated.coachingNotes,
            primaryMuscles: generated.primaryMuscles,
            secondaryMuscles: generated.secondaryMuscles,
            movementPatterns: generated.movementPatterns
        )
        exercise.apply(content)
        try context.save()
        return content
    }

    static func performanceFingerprint(
        for performance: ExercisePerformance
    ) throws -> String {
        let input = try performanceFingerprintInput(for: performance)
        if let cached = PerformanceFingerprintCache.shared.value(for: input.key) {
            return cached
        }
        let value = try hashPerformanceVideo(
            performanceID: input.performanceID,
            url: input.url
        )
        PerformanceFingerprintCache.shared.insert(value, for: input.key)
        return value
    }

    static func performanceFingerprintAsync(
        for performance: ExercisePerformance
    ) async throws -> String {
        let input = try performanceFingerprintInput(for: performance)
        if let cached = PerformanceFingerprintCache.shared.value(for: input.key) {
            return cached
        }
        let value = try await Task.detached(priority: .userInitiated) {
            try hashPerformanceVideo(
                performanceID: input.performanceID,
                url: input.url
            )
        }.value
        PerformanceFingerprintCache.shared.insert(value, for: input.key)
        return value
    }

    static func removeCachedPerformanceFingerprints() {
        PerformanceFingerprintCache.shared.removeAll()
    }

    private static func performanceFingerprintInput(
        for performance: ExercisePerformance
    ) throws -> (key: String, performanceID: UUID, url: URL) {
        guard let path = performance.activeVideoPath,
              let url = MediaStore.url(at: path)
        else {
            throw TrainingIntelligenceError.videoMissing
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? -1
        let key = [
            performance.id.uuidString,
            url.path,
            String(size),
            String(modified)
        ].joined(separator: "|")
        return (key, performance.id, url)
    }

    private nonisolated static func hashPerformanceVideo(
        performanceID: UUID,
        url: URL
    ) throws -> String {
        var hash = SHA256()
        hash.update(data: Data(performanceID.uuidString.utf8))
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1_048_576),
              !chunk.isEmpty
        {
            hash.update(data: chunk)
        }
        return hash.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func performanceReviewPrompt(
        performance: ExercisePerformance,
        sets: [WorkoutSet],
        fingerprint: String,
        in context: ModelContext
    ) throws -> String {
        try BusinessIDAllocator.assign(performance, namespace: "performance", in: context)
        guard let performanceID = performance.businessID else {
            throw TrainingIntelligenceError.performanceIDMissing
        }
        let completed = sets
            .filter {
                $0.performanceID == performance.id
                    && $0.status == .completed
            }
            .sorted { $0.order < $1.order }
        let setText = completed.map { set in
            [
                "第\(set.order)组",
                set.kind == .warmup ? "热身" : "工作组",
                set.actualWeightKG.map { "\($0.formatted())kg" },
                set.actualReps.map { "\($0)次" }
            ].compactMap { $0 }.joined(separator: " · ")
        }.joined(separator: "\n")
        return SomaPrompt.text("performance_review_user_prompt", [
            "exercise_name": performance.exerciseName,
            "performance_id": String(performanceID),
            "fingerprint": fingerprint,
            "sets": setText.isEmpty ? "未提供可确认的组数值" : setText
        ])
    }

    static func makePendingPerformanceVideo(
        performance: ExercisePerformance
    ) throws -> PendingAttachment {
        guard let path = performance.activeVideoPath,
              let url = MediaStore.url(at: path)
        else {
            throw TrainingIntelligenceError.videoMissing
        }
        return PendingAttachment(kind: .video, videoURL: url)
    }

    static func planFingerprint(
        prescriptions: [TemplateExercisePrescription],
        workouts: [WorkoutEntry]
    ) -> String {
        let prescriptionData = TrainingPlanCoding.encode(
            prescriptions.sorted { $0.order < $1.order }
        )
        let history = workouts.map {
            [
                $0.id.uuidString,
                $0.exerciseID?.uuidString ?? "",
                $0.date.timeIntervalSince1970.formatted(),
                ExerciseQuickFill.text(for: $0)
            ].joined(separator: "|")
        }.joined(separator: "\n")
        return digest(prescriptionData + Data(history.utf8))
    }

    private static func digest(_ value: Data) -> String {
        SHA256.hash(data: value).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from text: String
    ) throws -> T {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let value: String
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}")
        {
            value = String(trimmed[start ... end])
        } else {
            throw TrainingIntelligenceError.invalidModelOutput
        }
        do {
            return try JSONDecoder().decode(type, from: Data(value.utf8))
        } catch {
            throw TrainingIntelligenceError.invalidModelOutput
        }
    }
}

@MainActor
enum ExerciseImageGenerationService {
    static func generate(
        kind: ExerciseImageKind,
        for exercise: ExerciseDefinition,
        ai: AIService,
        in context: ModelContext
    ) async throws -> ExerciseImageReference {
        guard kind == .actionIllustration else {
            throw TrainingIntelligenceError.muscleMapGenerationRetired
        }
        let imageData = try await ai.generateImage(prompt: prompt(
            kind: kind,
            exercise: exercise
        ))
        let path = try await MediaStore.saveImageAsync(imageData)
        let reference = ExerciseImageReference(
            kind: kind,
            source: .generated,
            title: "AI 动作示意图",
            localPath: path
        )
        let original = exercise.imageReferences
        exercise.imageReferences = original + [reference]
        do {
            try context.save()
            return reference
        } catch {
            exercise.imageReferences = original
            context.rollback()
            _ = MediaStore.removeStoredFile(at: path)
            throw error
        }
    }

    static func prompt(
        kind: ExerciseImageKind,
        exercise: ExerciseDefinition
    ) -> String {
        switch kind {
        case .actionIllustration:
            SomaPrompt.text("exercise_illustration_prompt", ["exercise_name": exercise.canonicalName])
        case .muscleMap:
            "（已停用）肌群图改由 App 内程序化渲染，不再请求图像生成。"
        }
    }
}

enum TrainingIntelligenceError: LocalizedError, Equatable {
    case videoMissing
    case performanceIDMissing
    case invalidModelOutput
    case muscleMapGenerationRetired

    var errorDescription: String? {
        switch self {
        case .muscleMapGenerationRetired:
            "肌群受力图已改为程序化渲染，不再支持 AI 生成。"
        case .videoMissing:
            "这项动作没有可供复盘的本机视频。"
        case .performanceIDMissing:
            "无法取得这项训练的编号，请重新打开训练后重试。"
        case .invalidModelOutput:
            "模型没有按可审查格式返回结果，请重试。"
        }
    }
}
