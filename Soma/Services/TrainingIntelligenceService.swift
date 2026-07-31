import CryptoKit
import Foundation
import SwiftData

private struct GeneratedExerciseContent: Decodable {
    var coachingNotes: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var movementPatterns: [String]
}

@MainActor
enum TrainingIntelligenceService {
    static func optimize(
        program: TrainingProgram,
        prescriptions: [TemplateExercisePrescription],
        ai: AIService,
        in context: ModelContext
    ) async throws -> RecommendationSnapshot {
        let workouts = (
            try? context.fetch(
                FetchDescriptor<WorkoutEntry>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        let relevant = workouts.filter { workout in
            workout.exerciseID.map {
                Set(prescriptions.map(\.exerciseID)).contains($0)
            } ?? false
        }
        let fingerprint = planFingerprint(
            prescriptions: prescriptions,
            workouts: Array(relevant.prefix(30))
        )
        let existing = (
            try? context.fetch(FetchDescriptor<RecommendationSnapshot>())
        )?.first {
            $0.targetKind == "training_program"
                && $0.targetID == program.id
                && $0.inputFingerprint == fingerprint
        }
        if let existing {
            return existing
        }
        let prescriptionText = prescriptions
            .sorted { $0.order < $1.order }
            .map { item in
                [
                    "\(item.order). \(item.exerciseName)",
                    item.targetSets.map { "\($0)组" },
                    item.targetReps.map { "\($0)次" },
                    item.targetWeightKG.map { "\($0)kg" },
                    item.targetRestSeconds.map { "间歇\($0)秒" },
                    item.firstSetIsWarmup ? "首组热身" : nil
                ].compactMap { $0 }.joined(separator: " · ")
            }
            .joined(separator: "\n")
        let historyText = relevant.prefix(30).map {
            "\($0.date.formatted(date: .numeric, time: .omitted)) · \($0.exercise) · \(ExerciseQuickFill.text(for: $0))"
        }.joined(separator: "\n")
        let prompt = """
        用户主动请求优化训练计划“\(program.name)”。
        请只依据以下计划和真实历史，分别给出每个动作的建议重量、次数、组数与间歇；
        缺少证据时明确说“保持原计划”或“暂无足够历史”，不要虚构能力或健康事实。
        只输出面向用户的简洁建议，不调用任何工具，不改写计划。

        [计划]
        \(prescriptionText)

        [相关训练历史]
        \(historyText.isEmpty ? "暂无" : historyText)
        """
        let outcome = try await ai.runAgent(
            text: prompt,
            images: [],
            hasVideo: false,
            context: "这是用户主动触发的一次训练计划优化。建议是一般训练信息，不构成医疗诊断。"
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
    ) async throws -> ExerciseContentRevision {
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
        let revision = ExerciseContentRevision(
            source: .ai,
            coachingNotes: generated.coachingNotes,
            primaryMuscles: generated.primaryMuscles,
            secondaryMuscles: generated.secondaryMuscles,
            movementPatterns: generated.movementPatterns
        )
        exercise.apply(revision)
        try context.save()
        return revision
    }

    static func performanceFingerprint(
        for performance: ExercisePerformance
    ) throws -> String {
        guard let path = performance.activeVideoPath,
              let url = MediaStore.url(at: path)
        else {
            throw TrainingIntelligenceError.videoMissing
        }
        var hash = SHA256()
        hash.update(data: Data(performance.id.uuidString.utf8))
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

        请只依据本消息附带的视频或关键帧分析可见内容；单个阶段或关键帧不足时，不要描述为完整动作。
        不推断不可见关节、疼痛或伤病，不作医疗诊断。若出现疼痛、眩晕或明显不适，建议停止训练并寻求专业帮助。
        完成分析后必须调用 record_performance_analysis，原样传回上述 performance_id 和 input_fingerprint，
        并分别填写：按阶段描述的 evidence、镜头/遮挡/采样造成的 limitations、以及中性可执行的 feedback。
        不要调用 record_workout，也不要修改任何训练事实。
        """
    }

    static func existingPerformanceAnalysis(
        performance: ExercisePerformance,
        in context: ModelContext
    ) throws -> PerformanceAnalysis? {
        let fingerprint = try performanceFingerprint(for: performance)
        return (
            try? context.fetch(FetchDescriptor<PerformanceAnalysis>())
        )?.first(where: {
            $0.performanceID == performance.id
                && $0.inputFingerprint == fingerprint
        })
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
        let imageData = try await ai.generateImage(prompt: prompt(
            kind: kind,
            exercise: exercise
        ))
        let path = try MediaStore.saveImage(imageData)
        let reference = ExerciseImageReference(
            kind: kind,
            source: .generated,
            title: kind == .actionIllustration
                ? "AI 动作示意图"
                : "AI 通用肌群图",
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
            return """
            为私人健身记录 App Soma 生成“\(exercise.canonicalName)”动作示意图。
            正方形 1:1，暖白背景，单个成年人穿不透明运动服，以正确起始或最有辨识度的动作阶段展示，
            清楚呈现必要器械、身体姿势和动作方向。采用简洁、写实但克制的运动教学插画风格，
            全身完整入镜，移动端缩略图仍可辨认。不要文字、标签、数字、水印、Logo 或额外人物。
            这是一般动作示意，不描绘具体用户，也不作医疗诊断。
            """
        case .muscleMap:
            let primary = exercise.primaryMuscles.isEmpty
                ? "请依据该标准动作识别主要肌群"
                : exercise.primaryMuscles.joined(separator: "、")
            let secondary = exercise.secondaryMuscles.isEmpty
                ? "请依据该标准动作识别辅助肌群"
                : exercise.secondaryMuscles.joined(separator: "、")
            return """
            为私人健身记录 App Soma 生成“\(exercise.canonicalName)”的通用肌群示意图。
            正方形 1:1，暖白背景；并排展示正面与背面的中性合成人体解剖训练模型，
            全身中立站姿，穿不透明深灰运动短裤。肌肉以浅灰简化呈现。
            主要肌群（\(primary)）用橙色 #FF8A2A 着色；
            辅助肌群（\(secondary)）用金黄色 #FFC928 着色；其余保持灰色。
            解剖位置清楚、左右对称、留白充足，移动端卡片中可读。
            不要文字、标签、数字、水印、Logo 或器械。
            仅表达该动作通常涉及的肌群，不声称是用户个人受力测量，也不作医疗诊断。
            """
        }
    }
}

enum TrainingIntelligenceError: LocalizedError, Equatable {
    case videoMissing
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .videoMissing:
            "这项动作没有可供复盘的本机视频。"
        case .invalidModelOutput:
            "模型没有按可审查格式返回结果，请重试。"
        }
    }
}
