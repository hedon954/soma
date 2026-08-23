import Foundation
import SwiftData

extension ConversationRecorder {
    static func listTrainingPrograms(in context: ModelContext) -> AgentToolResult {
        let programs = ((try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? [])
            .filter {
                $0.status == .active
                    && !TrainingPlanStore.prescriptions(for: $0, in: context).isEmpty
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        let values = programs.map { program in
            "[id:\(program.businessID ?? 0)] \(program.name)"
                + "；概览：\(program.overview.isEmpty ? "未记录" : program.overview)"
                + "；动作：\(TrainingPlanStore.prescriptions(for: program, in: context).count) 个"
        }
        return .success(values.isEmpty ? "暂无可执行训练计划。" : values.joined(separator: "\n"))
    }

    static func getTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let programID = arguments.programID, programID > 0
        else {
            return .failure("get_training_program 需要有效的 program_id。")
        }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard let program = programs.first(where: { $0.businessID == programID }) else {
            return .failure("没有找到训练计划，请重新查询。")
        }
        let prescriptions = TrainingPlanStore.prescriptions(for: program, in: context)
        let exercises = prescriptions.map { prescription in
            let sets = prescription.plannedSets.sorted { $0.order < $1.order }
                .map { set in
                    let target = switch set.targetKind {
                    case .repetitions: "\(set.targetReps.map(String.init) ?? "未记录") 次"
                    case .duration: "\(set.targetDurationSeconds.map(String.init) ?? "未记录") 秒"
                    }
                    return "第 \(set.order) 组 \(target)"
                }
                .joined(separator: "；")
            return "\(prescription.order). \(prescription.exerciseName)（\(prescription.laterality.rawValue)）：\(sets)"
        }
        let overview = program.overview.isEmpty ? "未记录" : program.overview
        let header = "[id:\(program.businessID ?? 0)] \(program.name)；概览：\(overview)"
        return .success(
            "\(header)\n\(exercises.joined(separator: "\n"))",
            data: programData(
                program: program,
                prescriptions: prescriptions,
                in: context
            )
        )
    }

    static func createTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let name = nonempty(arguments.programName) else {
            return .failure("create_program 需要 program_name。")
        }
        do {
            let prescriptions = try planPrescriptions(arguments, in: context)
            let contentKey = TrainingPlanStore.contentFingerprint(prescriptions)
            let programs = ((try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? [])
                .filter { $0.status == .active }
            if let existing = programs.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                let current = TrainingPlanStore.prescriptions(for: existing, in: context)
                if TrainingPlanStore.contentFingerprint(current) == contentKey {
                    return .success(
                        "已有内容相同的训练计划 [id:\(existing.businessID ?? 0)]：\(existing.name)。"
                    )
                }
            }
            let program = try TrainingPlanStore.createProgram(
                name: name,
                goal: normalized(arguments.overview ?? arguments.goal),
                scheduleHint: normalized(arguments.scheduleHint),
                prescriptions: prescriptions,
                in: context
            )
            return .success(
                "已创建训练计划 [id:\(program.businessID ?? 0)]：\(program.name)。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func updateTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let programID = arguments.programID, programID > 0 else {
            return .failure("update_program 需要有效的 program_id。")
        }
        let programs = (
            try? context.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        guard let program = programs.first(where: { $0.businessID == programID }) else {
            return .failure("没有找到训练计划，请重新查询。")
        }
        do {
            try TrainingPlanStore.updateProgram(
                for: program,
                name: nonempty(arguments.programName) ?? program.name,
                scheduleHint: normalized(arguments.scheduleHint),
                prescriptions: planPrescriptions(arguments, in: context),
                in: context
            )
            return .success(
                "已更新训练计划 [id:\(program.businessID ?? 0)]：\(program.name)。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func archiveTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let programID = arguments.programID, programID > 0
        else {
            return .failure(
                "archive_training_program 需要有效的 program_id。"
            )
        }
        let programs = (
            try? context.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        guard let program = programs.first(where: { $0.businessID == programID }) else {
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
        guard let programID = arguments.programID, programID > 0
        else {
            return .failure("delete_training_program 需要有效的 program_id。")
        }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard let program = programs.first(where: { $0.businessID == programID }) else {
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
        guard let programID = arguments.programID, programID > 0
        else {
            return .failure("start_program 需要 list_programs 或 get_program 返回的有效 program_id。")
        }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard let program = programs.first(where: {
            $0.businessID == programID && $0.status == .active
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
                "已有未完成的「\(program.name)」带练 [session_id:\(existing.businessID ?? 0)]，已继续该 Session。"
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
                "已开始「\(program.name)」带练 [session_id:\(session.businessID ?? 0)]。"
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
        guard let performanceID = arguments.performanceID, performanceID > 0,
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
            $0.businessID == performanceID
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
                $0.performanceID == performance.id
                    && $0.inputFingerprint == fingerprint
            }) {
                return .success(
                    "该视频复盘已保存 [id:\(existing.businessID ?? 0)]。"
                )
            }
            let sourceJobID = sourceTurnID.flatMap { turnID in
                (
                    try? context.fetch(FetchDescriptor<AgentJob>())
                )?.first { $0.turnID == turnID }?.id
            }
            let analysis = PerformanceAnalysis(
                performanceID: performance.id,
                sourceMediaPath: path,
                inputFingerprint: fingerprint,
                evidence: evidence,
                limitations: limitations,
                feedback: feedback,
                sourceJobID: sourceJobID
            )
            context.insert(analysis)
            try BusinessIDAllocator.assign(
                analysis,
                namespace: "performance_analysis",
                in: context
            )
            try context.save()
            return .success(
                "已保存“\(performance.exerciseName)”视频复盘 [id:\(analysis.businessID ?? 0)]。"
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
            guard let definition = definitions.first(where: {
                $0.businessID == input.exerciseID && !$0.isArchived
            })
            else {
                throw ExerciseLibraryError.invalidReference
            }
            if let setInputs = input.setPrescriptions {
                guard let laterality = input.laterality else {
                    throw TrainingPlanError.invalidValue("动作侧别")
                }
                return TemplateExercisePrescription(
                    exerciseID: definition.id,
                    exerciseName: definition.canonicalName,
                    order: input.order,
                    targetRestSeconds: input.targetRestSeconds,
                    restBetweenSidesSeconds: input.restBetweenSidesSeconds,
                    equipmentKind: nonempty(input.equipmentKind),
                    notes: normalized(input.notes),
                    laterality: laterality,
                    plannedSets: setInputs.map { set in
                        TemplateSetPrescriptionValue(
                            order: set.order,
                            kind: set.kind,
                            targetKind: set.targetKind,
                            targetReps: set.targetReps,
                            targetDurationSeconds: set.targetDurationSeconds,
                            targetWeightKG: set.targetWeightKG,
                            leftWeightKG: set.leftWeightKG,
                            rightWeightKG: set.rightWeightKG,
                            notes: normalized(set.notes)
                        )
                    }
                )
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

    private static func programData(
        program: TrainingProgram,
        prescriptions: [TemplateExercisePrescription],
        in context: ModelContext
    ) -> AgentJSONValue {
        let definitions = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let definitionIDs = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
            definition.businessID.map { (definition.id, $0) }
        })
        return .object([
            "program_id": .number(Double(program.businessID ?? 0)),
            "program_name": .string(program.name),
            "overview": .string(program.overview),
            "schedule_hint": .string(program.scheduleHint),
            "exercises": .array(
                prescriptions.sorted { $0.order < $1.order }.map { prescription in
                    var exercise: [String: AgentJSONValue] = [
                        "exercise_id": .number(Double(definitionIDs[prescription.exerciseID] ?? 0)),
                        "exercise_name": .string(prescription.exerciseName),
                        "order": .number(Double(prescription.order)),
                        "laterality": .string(prescription.laterality.rawValue),
                        "set_prescriptions": .array(
                            prescription.plannedSets.sorted { $0.order < $1.order }
                                .map(setData)
                        )
                    ]
                    if let rest = prescription.targetRestSeconds {
                        exercise["target_rest_seconds"] = .number(Double(rest))
                    }
                    if let rest = prescription.restBetweenSidesSeconds {
                        exercise["rest_between_sides_seconds"] = .number(Double(rest))
                    }
                    if let equipment = nonempty(prescription.equipmentKind) {
                        exercise["equipment_kind"] = .string(equipment)
                    }
                    if let notes = nonempty(prescription.notes) {
                        exercise["notes"] = .string(notes)
                    }
                    return .object(exercise)
                }
            )
        ])
    }

    private static func setData(_ set: TemplateSetPrescriptionValue) -> AgentJSONValue {
        var value: [String: AgentJSONValue] = [
            "order": .number(Double(set.order)),
            "kind": .string(set.kind.rawValue),
            "target_kind": .string(set.targetKind.rawValue)
        ]
        func put(_ key: String, _ number: Int?) {
            if let number {
                value[key] = .number(Double(number))
            }
        }
        func put(_ key: String, _ number: Double?) {
            if let number {
                value[key] = .number(number)
            }
        }
        put("target_reps", set.targetReps)
        put("target_duration_seconds", set.targetDurationSeconds)
        put("target_weight_kg", set.targetWeightKG)
        put("left_weight_kg", set.leftWeightKG)
        put("right_weight_kg", set.rightWeightKG)
        if let notes = nonempty(set.notes) {
            value["notes"] = .string(notes)
        }
        return .object(value)
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func nonempty(_ value: String?) -> String? {
        let result = normalized(value)
        return result.isEmpty ? nil : result
    }
}
