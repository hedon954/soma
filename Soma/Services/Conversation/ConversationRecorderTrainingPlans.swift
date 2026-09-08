import Foundation
import SwiftData

extension ConversationRecorder {
    static func listTrainingPrograms(in context: ModelContext) -> AgentToolResult {
        let active = TrainingProgramStatus.active.rawValue
        var descriptor = FetchDescriptor<TrainingProgram>(
            predicate: #Predicate { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        // 每个计划只解析一次处方集合，不在过滤和描述里重复读同一关系。
        let values = ((try? context.fetch(descriptor)) ?? []).compactMap { program -> String? in
            let exerciseCount = TrainingPlanStore
                .prescriptions(for: program, in: context)
                .count
            guard exerciseCount > 0 else { return nil }
            return AgentFacingRecordID.labeled(program.businessID, summary: program.name, key: "program_id")
                + "；概览：\(program.overview.isEmpty ? "未记录" : program.overview)"
                + "；动作：\(exerciseCount) 个"
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
        guard let program = trainingProgram(businessID: programID, in: context) else {
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
        let header = "\(AgentFacingRecordID.labeled(program.businessID, summary: program.name, key: "program_id"))；概览：\(overview)"
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
            let sourceWorkouts = try sourceWorkouts(
                recordIDs: arguments.sourceWorkoutRecordIDs,
                prescriptions: prescriptions,
                in: context
            )
            let contentKey = TrainingPlanStore.contentFingerprint(prescriptions)
            let active = TrainingProgramStatus.active.rawValue
            var descriptor = FetchDescriptor<TrainingProgram>(
                predicate: #Predicate { $0.statusRaw == active }
            )
            descriptor.fetchLimit = 100
            let programs = (try? context.fetch(descriptor)) ?? []
            if let existing = programs.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                let current = TrainingPlanStore.prescriptions(for: existing, in: context)
                if TrainingPlanStore.contentFingerprint(current) == contentKey {
                    if !sourceWorkouts.isEmpty {
                        let session = try CompletedTrainingSessionMaterializer.materialize(
                            program: existing,
                            sourceWorkouts: sourceWorkouts,
                            in: context
                        )
                        return .success(
                            "已有内容相同的训练计划\(AgentFacingRecordID.trailing(existing.businessID, key: "program_id"))："
                                + "\(existing.name)；并已把当日训练保存为一次完成记录 "
                                + "[session_id:\(session.businessID ?? 0)]。"
                        )
                    }
                    return .success(
                        "已有内容相同的训练计划\(AgentFacingRecordID.trailing(existing.businessID, key: "program_id"))：\(existing.name)。"
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
            if !sourceWorkouts.isEmpty {
                let session = try CompletedTrainingSessionMaterializer.materialize(
                    program: program,
                    sourceWorkouts: sourceWorkouts,
                    in: context
                )
                return .success(
                    "已创建训练计划\(AgentFacingRecordID.trailing(program.businessID, key: "program_id"))：\(program.name)；"
                        + "并已把当日原始训练保存为一次完成记录 "
                        + "[session_id:\(session.businessID ?? 0)]。"
                )
            }
            return .success(
                "已创建训练计划\(AgentFacingRecordID.trailing(program.businessID, key: "program_id"))：\(program.name)。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func sourceWorkouts(
        recordIDs: [Int64]?,
        prescriptions: [TemplateExercisePrescription],
        in context: ModelContext
    ) throws -> [WorkoutEntry] {
        guard let recordIDs, !recordIDs.isEmpty else { return [] }
        guard recordIDs.count <= AgentBatchWriteLimit.maxItems,
              Set(recordIDs).count == recordIDs.count,
              recordIDs.allSatisfy({ $0 > 0 })
        else {
            throw TrainingPlanError.invalidValue("source_workout_record_ids")
        }
        let allowedExerciseIDs = Set(prescriptions.map(\.exerciseID))
        let workouts = try recordIDs.map { recordID -> WorkoutEntry in
            var descriptor = FetchDescriptor<WorkoutEntry>(
                predicate: #Predicate { $0.businessID == recordID }
            )
            descriptor.fetchLimit = 1
            guard let workout = try context.fetch(descriptor).first else {
                throw TrainingPlanError.invalidValue("找不到训练记录 \(recordID)")
            }
            guard let exerciseID = workout.exerciseID,
                  allowedExerciseIDs.contains(exerciseID)
            else {
                throw TrainingPlanError.invalidValue("训练记录 \(recordID) 的动作不在计划中")
            }
            return workout
        }
        let day = Calendar.current.startOfDay(for: workouts[0].date)
        guard workouts.allSatisfy({
            Calendar.current.startOfDay(for: $0.date) == day
                && $0.sourceWorkoutSessionID == nil
        }) else {
            throw TrainingPlanError.invalidValue("原始训练必须来自同一天且尚未归入其他 Session")
        }
        return workouts
    }

    static func updateTrainingProgram(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let programID = arguments.programID, programID > 0 else {
            return .failure("update_program 需要有效的 program_id。")
        }
        guard let program = trainingProgram(businessID: programID, in: context) else {
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
                "已更新训练计划\(AgentFacingRecordID.trailing(program.businessID, key: "program_id"))：\(program.name)。"
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
        guard let program = trainingProgram(businessID: programID, in: context) else {
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
        guard let program = trainingProgram(businessID: programID, in: context) else {
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
        guard let program = trainingProgram(businessID: programID, in: context),
              program.status == .active
        else {
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
        let programInternalID = program.id
        let draftStatus = WorkoutSessionStatus.draft.rawValue
        let activeStatus = WorkoutSessionStatus.active.rawValue
        let pausedStatus = WorkoutSessionStatus.paused.rawValue
        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.programID == programInternalID
                    && ($0.statusRaw == draftStatus
                        || $0.statusRaw == activeStatus
                        || $0.statusRaw == pausedStatus)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 1
        if let existing = try? context.fetch(sessionDescriptor).first {
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
        var performanceDescriptor = FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.businessID == performanceID }
        )
        performanceDescriptor.fetchLimit = 1
        guard let performance = try? context.fetch(performanceDescriptor).first,
              let path = performance.activeVideoPath
        else {
            return .failure("目标 Performance 或其当前视频已不存在。")
        }
        do {
            let expected = try TrainingIntelligenceService
                .performanceFingerprint(for: performance)
            guard expected == fingerprint else {
                return .failure("视频已变化，请基于当前视频重新发起复盘。")
            }
            let performanceInternalID = performance.id
            var analysisDescriptor = FetchDescriptor<PerformanceAnalysis>(
                predicate: #Predicate {
                    $0.performanceID == performanceInternalID
                        && $0.inputFingerprint == fingerprint
                }
            )
            analysisDescriptor.fetchLimit = 1
            if let existing = try? context.fetch(analysisDescriptor).first {
                return .success(
                    "该视频复盘已保存\(AgentFacingRecordID.trailing(existing.businessID))。"
                )
            }
            let sourceJobID = sourceTurnID.flatMap { turnID in
                var descriptor = FetchDescriptor<AgentJob>(
                    predicate: #Predicate { $0.turnID == turnID },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                return try? context.fetch(descriptor).first?.id
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
                "已保存“\(performance.exerciseName)”视频复盘\(AgentFacingRecordID.trailing(analysis.businessID))。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func trainingProgram(
        businessID: Int64,
        in context: ModelContext
    ) -> TrainingProgram? {
        var descriptor = FetchDescriptor<TrainingProgram>(
            predicate: #Predicate { $0.businessID == businessID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func exerciseDefinition(
        businessID: Int64,
        in context: ModelContext
    ) -> ExerciseDefinition? {
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.businessID == businessID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func exerciseDefinition(
        internalID: UUID,
        in context: ModelContext
    ) -> ExerciseDefinition? {
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.id == internalID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func planPrescriptions(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) throws -> [TemplateExercisePrescription] {
        guard let inputs = arguments.templateExercises, !inputs.isEmpty else {
            throw TrainingPlanError.emptyTemplate
        }
        return try inputs.map { input in
            guard let definition = exerciseDefinition(
                businessID: input.exerciseID,
                in: context
            ), !definition.isArchived
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
        let definitionIDs = prescriptions.reduce(into: [UUID: Int64]()) { result, prescription in
            guard result[prescription.exerciseID] == nil,
                  let definition = exerciseDefinition(
                      internalID: prescription.exerciseID,
                      in: context
                  ), let businessID = definition.businessID
            else {
                return
            }
            result[definition.id] = businessID
        }
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
