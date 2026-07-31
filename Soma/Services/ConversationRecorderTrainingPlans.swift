import Foundation
import SwiftData

extension ConversationRecorder {
    static func createTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let name = nonempty(arguments.programName),
              let templateName = nonempty(arguments.templateName)
        else {
            return .failure(
                "create_training_program 需要 program_name 和 template_name。"
            )
        }
        do {
            let program = try TrainingPlanStore.createProgram(
                name: name,
                goal: normalized(arguments.goal),
                templateName: templateName,
                scheduleHint: normalized(arguments.scheduleHint),
                prescriptions: planPrescriptions(arguments, in: context),
                source: "agent",
                in: context
            )
            return .success(
                "已创建训练计划 [id:\(program.id.uuidString)]：\(program.name)。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func createWorkoutTemplateVersion(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let rawID = arguments.programID,
              let programID = UUID(uuidString: rawID),
              let templateName = nonempty(arguments.templateName)
        else {
            return .failure(
                "更新训练模板需要有效的 program_id 和 template_name。"
            )
        }
        let programs = (
            try? context.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        guard let program = programs.first(where: { $0.id == programID }) else {
            return .failure("没有找到训练计划，请重新查询。")
        }
        do {
            let version = try TrainingPlanStore.createNextVersion(
                for: program,
                name: templateName,
                scheduleHint: normalized(arguments.scheduleHint),
                prescriptions: planPrescriptions(arguments, in: context),
                source: "agent",
                in: context
            )
            return .success(
                "已为计划 [id:\(program.id.uuidString)] 创建模板 v\(version.version) [id:\(version.id.uuidString)]。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func archiveTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let rawID = arguments.programID,
              let programID = UUID(uuidString: rawID)
        else {
            return .failure(
                "archive_training_program 需要有效的 program_id。"
            )
        }
        let programs = (
            try? context.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        guard let program = programs.first(where: { $0.id == programID }) else {
            return .failure("没有找到训练计划，请重新查询。")
        }
        do {
            try TrainingPlanStore.archive(program, in: context)
            return .success("已归档训练计划：\(program.name)。")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func recordPerformanceAnalysis(
        _ arguments: AgentToolArguments,
        sourceTurnID: UUID?,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let rawID = arguments.performanceID,
              let performanceID = UUID(uuidString: rawID),
              let fingerprint = nonempty(arguments.inputFingerprint),
              let evidence = nonempty(arguments.evidence),
              let limitations = nonempty(arguments.limitations),
              let feedback = nonempty(arguments.feedback)
        else {
            return .failure(
                "record_performance_analysis 缺少 Performance、输入指纹或可审查反馈。"
            )
        }
        let performances = (
            try? context.fetch(FetchDescriptor<ExercisePerformance>())
        ) ?? []
        guard let performance = performances.first(where: {
            $0.id == performanceID
        }), let path = performance.activeVideoPath
        else {
            return .failure("目标 Performance 或其当前视频已不存在。")
        }
        do {
            let expected = try TrainingIntelligenceService
                .performanceFingerprint(for: performance)
            guard expected == fingerprint else {
                return .failure("视频已变化，请基于当前视频重新发起复盘。")
            }
            let analyses = (
                try? context.fetch(FetchDescriptor<PerformanceAnalysis>())
            ) ?? []
            if let existing = analyses.first(where: {
                $0.performanceID == performanceID
                    && $0.inputFingerprint == fingerprint
            }) {
                return .success(
                    "该视频复盘已保存 [id:\(existing.id.uuidString)]。"
                )
            }
            let sourceJobID = sourceTurnID.flatMap { turnID in
                (
                    try? context.fetch(FetchDescriptor<AgentJob>())
                )?.first { $0.turnID == turnID }?.id
            }
            let analysis = PerformanceAnalysis(
                performanceID: performanceID,
                sourceMediaPath: path,
                inputFingerprint: fingerprint,
                evidence: evidence,
                limitations: limitations,
                feedback: feedback,
                sourceJobID: sourceJobID
            )
            context.insert(analysis)
            try context.save()
            return .success(
                "已保存“\(performance.exerciseName)”视频复盘 [id:\(analysis.id.uuidString)]。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func planPrescriptions(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) throws -> [TemplateExercisePrescription] {
        guard let inputs = arguments.templateExercises, !inputs.isEmpty else {
            throw TrainingPlanError.emptyTemplate
        }
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        return try inputs.map { input in
            guard let id = UUID(uuidString: input.exerciseID),
                  let definition = definitions.first(where: {
                      $0.id == id && !$0.isArchived
                  })
            else {
                throw ExerciseLibraryError.invalidReference
            }
            return TemplateExercisePrescription(
                exerciseID: definition.id,
                exerciseName: definition.canonicalName,
                order: input.order,
                targetSets: input.targetSets,
                targetReps: input.targetReps,
                targetWeightKG: input.targetWeightKG,
                targetRestSeconds: input.targetRestSeconds,
                firstSetIsWarmup: input.firstSetIsWarmup ?? false,
                equipmentKind: nonempty(input.equipmentKind),
                notes: normalized(input.notes)
            )
        }
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func nonempty(_ value: String?) -> String? {
        let result = normalized(value)
        return result.isEmpty ? nil : result
    }
}
