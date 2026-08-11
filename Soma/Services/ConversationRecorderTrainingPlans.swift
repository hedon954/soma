import Foundation
import SwiftData

extension ConversationRecorder {
    static func listTrainingPrograms(in context: ModelContext) -> AgentToolResult {
        let programs = ((try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? [])
            .filter { $0.status == .active && $0.currentTemplateVersionID != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        let versions = (try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>())) ?? []
        let values = programs.map { program in
            let template = versions.first { $0.id == program.currentTemplateVersionID }
            return "[id:\(program.id.uuidString)] \(program.name)"
                + "；目标：\(program.goal.isEmpty ? "未记录" : program.goal)"
                + "；当前模板：\(template?.name ?? "未找到")"
        }
        return .success(values.isEmpty ? "暂无可执行训练计划。" : values.joined(separator: "\n"))
    }

    static func getTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let rawID = arguments.programID,
              let programID = UUID(uuidString: rawID)
        else {
            return .failure("get_training_program 需要有效的 program_id。")
        }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard let program = programs.first(where: { $0.id == programID }),
              let versionID = program.currentTemplateVersionID,
              let version = ((try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>())) ?? [])
              .first(where: { $0.id == versionID })
        else {
            return .failure("没有找到训练计划或其当前模板，请重新查询。")
        }
        let prescriptions = TrainingPlanStore.prescriptions(for: version, in: context)
        let exercises = prescriptions.map { prescription in
            "\(prescription.order). \(prescription.exerciseName)：\(prescription.targetSets.map(String.init) ?? "未记录")组 × \(prescription.targetReps.map(String.init) ?? "未记录")次"
        }
        let goal = program.goal.isEmpty ? "未记录" : program.goal
        let header = "[id:\(program.id.uuidString)] \(program.name)；目标：\(goal)；模板：\(version.name) v\(version.version)"
        return .success(
            "\(header)\n\(exercises.joined(separator: "\n"))"
        )
    }

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
            let prescriptions = try planPrescriptions(arguments, in: context)
            let contentKey = TrainingPlanStore.contentFingerprint(prescriptions)
            let programs = ((try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? [])
                .filter { $0.status == .active }
            let versions = (try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>())) ?? []
            if let existing = programs.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }),
                let version = versions.first(where: {
                    $0.id == existing.currentTemplateVersionID
                })
            {
                let current = TrainingPlanStore.prescriptions(for: version, in: context)
                if TrainingPlanStore.contentFingerprint(current) == contentKey {
                    return .success(
                        "已有内容相同的训练计划 [id:\(existing.id.uuidString)]：\(existing.name)。"
                    )
                }
            }
            let program = try TrainingPlanStore.createProgram(
                name: name,
                goal: normalized(arguments.goal),
                templateName: templateName,
                scheduleHint: normalized(arguments.scheduleHint),
                prescriptions: prescriptions,
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

    static func deleteTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let rawID = arguments.programID,
              let programID = UUID(uuidString: rawID)
        else {
            return .failure("delete_training_program 需要有效的 program_id。")
        }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard let program = programs.first(where: { $0.id == programID }) else {
            return .failure("没有找到训练计划，请重新查询。")
        }
        do {
            try TrainingPlanStore.deleteProgram(program, in: context)
            return .success("已永久删除训练计划：\(program.name)；既有训练历史仍保留。")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func startGuidedWorkout(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let rawID = arguments.programID,
              let programID = UUID(uuidString: rawID)
        else {
            return .failure("start_guided_workout 需要 query_user_data 返回的有效 program_id。")
        }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard let program = programs.first(where: {
            $0.id == programID && $0.status == .active
        }) else {
            return .failure("没有找到可执行的训练计划，请重新查询。")
        }
        let policy: AutoRecordingPolicy
        switch arguments.autoRecordingPolicy {
        case nil, "disabled": policy = .disabled
        case "one_per_exercise": policy = .enabled
        case "every_set": policy = .everySet
        default:
            return .failure("录像策略仅支持 disabled、one_per_exercise 或 every_set。")
        }
        let sessions = (
            try? context.fetch(
                FetchDescriptor<WorkoutSession>(
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
            )
        ) ?? []
        if let existing = sessions.first(where: {
            $0.programID == program.id
                && [.draft, .active, .paused].contains($0.status)
        }) {
            SomaCaptureRouter.shared.requestWorkoutSession(existing.id)
            return .success(
                "已有未完成的「\(program.name)」带练 [session_id:\(existing.id.uuidString)]，已继续该 Session。"
            )
        }
        do {
            let session = try TrainingPlanStore.startSession(
                program: program,
                autoRecordingPolicy: policy,
                in: context
            )
            SomaCaptureRouter.shared.requestWorkoutSession(session.id)
            return .success(
                "已开始「\(program.name)」带练 [session_id:\(session.id.uuidString)]。"
            )
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
