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
        let prompt = """
        用户主动请求优化训练课程“\(program.name)”。
        请只依据以下计划和真实历史，分别给出每个动作的建议重量、次数、组数与间歇；
        缺少证据时明确说“保持原课程”或“暂无足够历史”，不要虚构能力或健康事实。
        只输出面向用户的简洁建议，不调用任何工具，不改写课程。

        [课程]
        \(prescriptionText)

        [相关训练历史]
        \(historyText.isEmpty ? "暂无" : historyText)
        """
        let outcome = try await ai.runAgent(
            text: prompt,
            images: [],
            hasVideo: false,
            context: "这是用户主动触发的一次训练课程优化。建议是一般训练信息，不构成医疗诊断。"
        ) { _ in
            .failure("计划优化流程不执行 Tool；请直接返回建议。")
        }
        let snapshot = RecommendationSnapshot(
            targetKind: "training_program",
            targetID: program.id,
            inputFingerprint: fingerprint,
            advice: outcome.finalAnswer
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
        let prompt = """
        用户主动请求生成“\(exercise.canonicalName)”的动作说明。
        只返回一个 JSON 对象，不要 Markdown：
        {
          "coachingNotes": "简洁的准备、执行、呼吸和常见错误提示，包含不适时停止训练的安全提醒",
          "primaryMuscles": ["主要肌群"],
          "secondaryMuscles": ["辅助肌群"],
          "movementPatterns": ["动作模式"]
        }
        内容是一般训练指导，不作诊断；肌群仅描述通用主要和辅助参与，不描述为用户个人受力结果。
        """
        let outcome = try await ai.runAgent(
            text: prompt,
            images: [],
            hasVideo: false,
            context: "这是用户主动触发的动作内容生成。"
        ) { _ in
            .failure("动作内容生成流程不执行 Tool；请直接返回 JSON。")
        }
        let generated = try decodeJSON(
            GeneratedExerciseContent.self,
            from: outcome.finalAnswer
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
        fingerprint: String
    ) -> String {
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
        return """
        我主动请求复盘这段“\(performance.exerciseName)”训练视频。
        关联 Performance ID：\(performance.id.uuidString)
        输入指纹：\(fingerprint)
        已确认的实际组：
        \(setText.isEmpty ? "未提供可确认的组数值" : setText)

        请只依据本消息附带的完整视频分析可见内容；可见证据不足时，不要描述为完整动作。
        不推断不可见关节、疼痛或伤病，不作医疗诊断。若出现疼痛、眩晕或明显不适，建议停止训练并寻求专业帮助。
        完成分析后必须调用 record_performance_analysis，原样传回上述 performance_id 和 input_fingerprint，
        并分别填写：按阶段描述的 evidence、镜头/遮挡/采样造成的 limitations、以及中性可执行的 feedback。
        不要调用 create_workout 或 update_workout，也不要修改任何训练事实。
        """
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
            """
            为私人健身记录 App Soma 生成“\(exercise.canonicalName)”动作示意图。
            正方形 1:1，浅灰白干净背景（#F4F6F5），单个成年人穿不透明深灰短袖与黑色短裤，
            以正确起始或最有辨识度的动作阶段展示，清楚呈现必要器械、身体姿势和动作方向。
            风格必须统一：扁平化矢量运动教学插画、边缘清晰、无厚重阴影、无写实皮肤纹理、
            无油画感；配色克制，主色贴近 Soma 绿色 #1FB25E 作为点缀即可。
            全身完整入镜，移动端缩略图仍可辨认。不要文字、标签、数字、水印、Logo 或额外人物。
            这是一般动作示意，不描绘具体用户，也不作医疗诊断。
            """
        case .muscleMap:
            """
            （已停用）肌群图改由 App 内程序化渲染，不再请求图像生成。
            """
        }
    }
}

enum TrainingIntelligenceError: LocalizedError, Equatable {
    case videoMissing
    case invalidModelOutput
    case muscleMapGenerationRetired

    var errorDescription: String? {
        switch self {
        case .muscleMapGenerationRetired:
            "肌群受力图已改为程序化渲染，不再支持 AI 生成。"
        case .videoMissing:
            "这项动作没有可供复盘的本机视频。"
        case .invalidModelOutput:
            "模型没有按可审查格式返回结果，请重试。"
        }
    }
}
