import CryptoKit
import Foundation
import SwiftData

enum TrainingPlanError: LocalizedError, Equatable {
    case emptyName
    case emptyTemplate
    case missingExercise(UUID)
    case duplicateOrder(Int)
    case invalidSets
    case invalidValue(String)
    case missingTemplate
    case immutableSession

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "计划名称不能为空。"
        case .emptyTemplate:
            "训练模板至少需要一个动作。"
        case let .missingExercise(id):
            "动作 \(id.uuidString) 已不存在，请替换后再开始。"
        case let .duplicateOrder(order):
            "动作顺序 \(order) 重复。"
        case .invalidSets:
            "计划组数必须在 1 到 100 之间。"
        case let .invalidValue(field):
            "\(field) 超出合法范围。"
        case .missingTemplate:
            "当前训练模板不存在。"
        case .immutableSession:
            "已开始或已结束的训练快照不能被计划修改。"
        }
    }
}

struct TrainingReadinessIssue: Equatable, Identifiable, Sendable {
    enum Severity: String, Sendable {
        case warning
        case blocking
    }

    var id: String
    var severity: Severity
    var message: String
}

struct TrainingSessionSummary: Equatable, Sendable {
    var completedSets: Int
    var partialSets: Int = 0
    var skippedSets: Int
    var failedSets: Int = 0
    var completedVolume: Double
    var exerciseCount: Int
    var durationSeconds: Int
    var recordedVideoCount: Int
    var estimatedCalories: Int?
    var exercises: [TrainingExerciseSummary]

    var text: String {
        var values = [
            "完成 \(exerciseCount) 个动作",
            "\(completedSets) 组"
        ]
        if skippedSets > 0 {
            values.append("跳过 \(skippedSets) 组")
        }
        if partialSets > 0 {
            values.append("部分完成 \(partialSets) 组")
        }
        if failedSets > 0 {
            values.append("失败 \(failedSets) 组")
        }
        if completedVolume > 0 {
            values.append(
                "有效容量 \(completedVolume.formatted(.number.precision(.fractionLength(0 ... 1)))) kg"
            )
        }
        if recordedVideoCount > 0 {
            values.append("录制 \(recordedVideoCount) 组")
        }
        if let estimatedCalories {
            values.append("约 \(estimatedCalories) 千卡")
        }
        return values.joined(separator: "，") + "。"
    }

    var durationText: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return minutes > 0 ? "\(minutes) 分 \(seconds) 秒" : "\(seconds) 秒"
    }
}

struct TrainingExerciseSummary: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var completedSets: Int
    var partialSets: Int = 0
    var skippedSets: Int
    var failedSets: Int = 0
    var completedVolume: Double
}

@MainActor
enum TrainingPlanStore {
    /// 计划模板内容指纹，用于 Agent 创建时识别同名同内容重复。
    static func contentFingerprint(
        _ prescriptions: [TemplateExercisePrescription]
    ) -> String {
        let data = TrainingPlanCoding.encode(
            prescriptions.sorted { $0.order < $1.order }
        )
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func createProgram(
        name: String,
        goal: String = "",
        scheduleHint: String = "",
        prescriptions: [TemplateExercisePrescription],
        in context: ModelContext
    ) throws -> TrainingProgram {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw TrainingPlanError.emptyName }
        try validate(prescriptions, in: context)

        let program = TrainingProgram(
            name: normalizedName,
            goal: goal,
            scheduleHint: scheduleHint
        )
        context.insert(program)
        insert(prescriptions, program: program, in: context)
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
        return program
    }

    static func updateOverview(
        _ overview: String,
        for program: TrainingProgram,
        in context: ModelContext
    ) throws {
        program.overview = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        program.updatedAt = .now
        try context.save()
    }

    static func updateProgram(
        for program: TrainingProgram,
        name: String,
        scheduleHint: String,
        prescriptions: [TemplateExercisePrescription],
        in context: ModelContext
    ) throws {
        try validate(prescriptions, in: context)
        let existing = templateExercises(for: program, in: context)
        let sets = existing.flatMap { exercise in
            guard exercise.setPrescriptions.isEmpty else {
                return exercise.setPrescriptions
            }
            let exerciseID = exercise.id
            return (try? context.fetch(
                FetchDescriptor<TemplateSetPrescription>(
                    predicate: #Predicate {
                        $0.templateExerciseID == exerciseID
                    }
                )
            )) ?? []
        }
        sets.forEach { context.delete($0) }
        existing.forEach { context.delete($0) }
        program.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        program.scheduleHint = scheduleHint.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        insert(prescriptions, program: program, in: context)
        program.updatedAt = .now
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
    }

    static func prescriptions(
        for program: TrainingProgram,
        in context: ModelContext
    ) -> [TemplateExercisePrescription] {
        let exercises = templateExercises(for: program, in: context)
            .sorted { $0.order < $1.order }
        return exercises.map { exercise in
            let relatedSets = exercise.setPrescriptions
            let exerciseID = exercise.id
            let fallbackSets = relatedSets.isEmpty
                ? ((try? context.fetch(
                    FetchDescriptor<TemplateSetPrescription>(
                        predicate: #Predicate {
                            $0.templateExerciseID == exerciseID
                        }
                    )
                )) ?? [])
                : []
            let plannedSets = (relatedSets.isEmpty ? fallbackSets : relatedSets)
                .sorted { $0.order < $1.order }
                .map(\.value)
            let definitionName: String? = if let related = exercise.exerciseDefinition {
                related.canonicalName
            } else {
                {
                    let targetID = exercise.exerciseID
                    var descriptor = FetchDescriptor<ExerciseDefinition>(
                        predicate: #Predicate { $0.id == targetID }
                    )
                    descriptor.fetchLimit = 1
                    return (try? context.fetch(descriptor))?.first?.canonicalName
                }()
            }
            return TemplateExercisePrescription(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                exerciseName: definitionName ?? "已删除动作",
                order: exercise.order,
                targetSets: exercise.targetSets,
                targetReps: exercise.targetReps,
                targetWeightKG: exercise.targetWeightKG,
                targetRestSeconds: exercise.targetRestSeconds,
                restBetweenSidesSeconds: exercise.restBetweenSidesSeconds,
                firstSetIsWarmup: exercise.firstSetIsWarmup,
                equipmentKind: exercise.equipmentKind,
                notes: exercise.notes,
                laterality: exercise.laterality,
                plannedSets: plannedSets.isEmpty ? nil : plannedSets
            )
        }
    }

    /// Current schema writes the complete program graph with relationships.
    /// Views use this graph-only projection so a body update never falls back
    /// to database queries for each exercise and planned set.
    static func currentPrescriptions(
        for program: TrainingProgram
    ) -> [TemplateExercisePrescription] {
        program.templateExercises
            .sorted { $0.order < $1.order }
            .map { exercise in
                let plannedSets = exercise.setPrescriptions
                    .sorted { $0.order < $1.order }
                    .map(\.value)
                return TemplateExercisePrescription(
                    id: exercise.id,
                    exerciseID: exercise.exerciseID,
                    exerciseName: exercise.exerciseDefinition?.canonicalName
                        ?? "已删除动作",
                    order: exercise.order,
                    targetSets: exercise.targetSets,
                    targetReps: exercise.targetReps,
                    targetWeightKG: exercise.targetWeightKG,
                    targetRestSeconds: exercise.targetRestSeconds,
                    restBetweenSidesSeconds: exercise.restBetweenSidesSeconds,
                    firstSetIsWarmup: exercise.firstSetIsWarmup,
                    equipmentKind: exercise.equipmentKind,
                    notes: exercise.notes,
                    laterality: exercise.laterality,
                    plannedSets: plannedSets.isEmpty ? nil : plannedSets
                )
            }
    }

    private static func templateExercises(
        for program: TrainingProgram,
        in context: ModelContext
    ) -> [TemplateExercise] {
        let related = program.templateExercises
        guard related.isEmpty else { return related }
        guard let groupID = program.prescriptionGroupID else { return [] }
        return (
            try? context.fetch(
                FetchDescriptor<TemplateExercise>(
                    predicate: #Predicate {
                        $0.prescriptionGroupID == groupID
                    }
                )
            )
        ) ?? []
    }

    private static func definitions(
        for exerciseIDs: Set<UUID>,
        in context: ModelContext
    ) -> [UUID: ExerciseDefinition] {
        guard !exerciseIDs.isEmpty else { return [:] }
        // 一次 IN 查询代替逐 ID 往返，避免计划越大数据库调用越多。
        let descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { exerciseIDs.contains($0.id) }
        )
        return ((try? context.fetch(descriptor)) ?? [])
            .reduce(into: [:]) { result, definition in
                result[definition.id] = definition
            }
    }

    static func readiness(
        prescriptions: [TemplateExercisePrescription],
        autoRecording: Bool,
        availableEquipment: Set<String> = [],
        in context: ModelContext
    ) -> [TrainingReadinessIssue] {
        readiness(
            prescriptions: prescriptions,
            autoRecordingPolicy: autoRecording ? .enabled : .disabled,
            availableEquipment: availableEquipment,
            in: context
        )
    }

    static func readiness(
        prescriptions: [TemplateExercisePrescription],
        autoRecordingPolicy: AutoRecordingPolicy,
        availableEquipment: Set<String> = [],
        in context: ModelContext
    ) -> [TrainingReadinessIssue] {
        var issues: [TrainingReadinessIssue] = []
        do {
            try validate(prescriptions, in: context)
        } catch let error as TrainingPlanError {
            issues.append(issue(
                "strict-prescription",
                .blocking,
                error.errorDescription ?? "训练参数无效。"
            ))
        } catch {
            issues.append(issue(
                "strict-prescription",
                .blocking,
                "训练参数无法验证。"
            ))
        }
        if prescriptions.isEmpty {
            issues.append(issue(
                "empty",
                .blocking,
                "训练模板至少需要一个动作。"
            ))
        }
        let definitions = definitions(
            for: Set(prescriptions.map(\.exerciseID)),
            in: context
        )
        let activeIDs = Set(definitions.values.filter { !$0.isArchived }.map(\.id))
        for prescription in prescriptions {
            if !activeIDs.contains(prescription.exerciseID) {
                issues.append(issue(
                    "exercise-\(prescription.id)",
                    .blocking,
                    "“\(prescription.exerciseName)”已不存在或归档。"
                ))
            }
            if prescription.plannedSets.isEmpty {
                issues.append(issue(
                    "sets-\(prescription.id)",
                    .blocking,
                    "“\(prescription.exerciseName)”至少需要一个有效组。"
                ))
            }
            if autoRecordingPolicy == .enabled,
               !prescription.plannedSets.contains(where: { $0.kind == .working })
            {
                issues.append(issue(
                    "recording-\(prescription.id)",
                    .warning,
                    "“\(prescription.exerciseName)”没有工作组，无法自动执行首工作组录像。"
                ))
            }
            if let equipment = prescription.equipmentKind,
               !equipment.isEmpty,
               !availableEquipment.isEmpty,
               !availableEquipment.contains(equipment)
            {
                issues.append(issue(
                    "equipment-\(prescription.id)",
                    .warning,
                    "当前健身房没有记录“\(equipment)”。"
                ))
            }
        }
        for order in Dictionary(grouping: prescriptions, by: \.order)
            where order.value.count > 1
        {
            issues.append(issue(
                "order-\(order.key)",
                .blocking,
                "动作顺序 \(order.key) 重复。"
            ))
        }
        return issues
    }

    static func startSession(
        program: TrainingProgram,
        gymID: UUID? = nil,
        autoRecordingPolicy: AutoRecordingPolicy = .disabled,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let values = prescriptions(for: program, in: context)
        guard !values.isEmpty else { throw TrainingPlanError.missingTemplate }
        try validate(values, in: context)
        let blocking = readiness(
            prescriptions: values,
            autoRecordingPolicy: autoRecordingPolicy,
            in: context
        ).contains { $0.severity == .blocking }
        guard !blocking else { throw TrainingPlanError.emptyTemplate }

        let session = WorkoutSession(
            gymID: gymID,
            programID: program.id,
            programNameSnapshot: program.name,
            prescriptionSnapshot: values,
            status: .active,
            autoRecordingPolicy: autoRecordingPolicy
        )
        context.insert(session)
        let definitions = definitions(
            for: Set(values.map(\.exerciseID)),
            in: context
        )
        var firstPerformance: ExercisePerformance?
        var firstSet: WorkoutSet?
        var firstEffort: WorkoutEffort?

        for prescription in values.sorted(by: { $0.order < $1.order }) {
            let performance = ExercisePerformance(
                sessionID: session.id,
                exerciseID: prescription.exerciseID,
                exerciseName: prescription.exerciseName,
                order: prescription.order,
                prescriptionSnapshot: prescription
            )
            performance.session = session
            context.insert(performance)
            if firstPerformance == nil {
                firstPerformance = performance
            }
            performance.exerciseDefinition = definitions[prescription.exerciseID]
            if let definition = performance.exerciseDefinition {
                ExerciseLoggingProfile.adoptIfUnset(
                    definition,
                    laterality: prescription.laterality,
                    targetKind: prescription.plannedSets.first?.targetKind
                )
            }
            let laterality = performance.exerciseDefinition?.hasExplicitLaterality == true
                ? performance.exerciseDefinition?.laterality ?? prescription.laterality
                : prescription.laterality
            let orderedSets = prescription.plannedSets.sorted { $0.order < $1.order }
            for (setIndex, planned) in orderedSets.enumerated() {
                let targetKind = performance.exerciseDefinition?.hasExplicitTargetKind == true
                    ? performance.exerciseDefinition?.targetKind ?? planned.targetKind
                    : planned.targetKind
                let set = WorkoutSet(
                    performanceID: performance.id,
                    order: planned.order,
                    kind: planned.kind,
                    laterality: laterality.rawValue,
                    plannedTargetKind: targetKind,
                    plannedReps: planned.targetReps,
                    plannedDurationSeconds: planned.targetDurationSeconds,
                    plannedWeightKG: planned.targetWeightKG,
                    plannedRestSeconds: setIndex < orderedSets.count - 1
                        ? prescription.targetRestSeconds
                        : nil,
                    restBetweenSidesSeconds: laterality == .both
                        ? prescription.restBetweenSidesSeconds
                        : nil
                )
                set.performance = performance
                context.insert(set)
                if firstSet == nil {
                    firstSet = set
                }
                let sides: [WorkoutEffortSide] = switch laterality {
                case .both:
                    [.left, .right]
                case .left:
                    [.left]
                case .right:
                    [.right]
                case .none:
                    [.none]
                }
                for (index, side) in sides.enumerated() {
                    let effort = WorkoutEffort(
                        workoutSetID: set.id,
                        order: index + 1,
                        side: side,
                        targetKind: targetKind,
                        plannedReps: planned.targetReps,
                        plannedDurationSeconds: planned.targetDurationSeconds,
                        plannedWeightKG: planned.weight(for: side)
                    )
                    effort.workoutSet = set
                    context.insert(effort)
                    if firstEffort == nil {
                        firstEffort = effort
                    }
                }
            }
        }
        session.currentPerformanceID = firstPerformance?.id
        session.currentSetID = firstSet?.id
        session.currentEffortID = firstEffort?.id
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
        return session
    }

    static func startSession(
        program: TrainingProgram,
        gymID: UUID? = nil,
        autoRecording: Bool,
        in context: ModelContext
    ) throws -> WorkoutSession {
        try startSession(
            program: program,
            gymID: gymID,
            autoRecordingPolicy: autoRecording ? .enabled : .disabled,
            in: context
        )
    }

    static func summary(
        for sessionID: UUID,
        in context: ModelContext
    ) -> TrainingSessionSummary {
        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        let session = (try? context.fetch(sessionDescriptor))?.first
        guard let session else {
            return TrainingSessionSummaryCalculator.make(
                session: nil,
                performances: [],
                sets: [],
                efforts: [],
                workoutsByPerformanceID: [:]
            )
        }
        return summary(for: session)
    }

    /// marker 6 和当前恢复流程已修复 Session → Performance → Set → Effort
    /// 及投影关系；最新版运行时只读关系图，不再为旧缺失关系逐项补查。
    static func summary(for session: WorkoutSession) -> TrainingSessionSummary {
        let performances = session.performances
        let sets = performances.flatMap(\.workoutSets)
        let efforts = sets.flatMap(\.efforts)
        let workoutsByPerformanceID = performances.reduce(
            into: [UUID: WorkoutEntry]()
        ) { result, performance in
            guard !performance.workoutProjectionSuppressed,
                  let projectedWorkout = performance.projectedWorkout
            else { return }
            result[performance.id] = projectedWorkout
        }
        return TrainingSessionSummaryCalculator.make(
            session: session,
            performances: performances,
            sets: sets,
            efforts: efforts,
            workoutsByPerformanceID: workoutsByPerformanceID
        )
    }

    static func deleteSession(
        _ session: WorkoutSession,
        in context: ModelContext
    ) throws {
        let sessionID = session.id
        let performances = session.performances.isEmpty
            ? try context.fetch(FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.sessionID == sessionID }
            ))
            : session.performances
        let sets = performances.flatMap { performance in
            guard performance.workoutSets.isEmpty else {
                return performance.workoutSets
            }
            let performanceID = performance.id
            return (try? context.fetch(FetchDescriptor<WorkoutSet>(
                predicate: #Predicate { $0.performanceID == performanceID }
            ))) ?? []
        }
        let efforts = sets.flatMap { set in
            guard set.efforts.isEmpty else { return set.efforts }
            let setID = set.id
            return (try? context.fetch(FetchDescriptor<WorkoutEffort>(
                predicate: #Predicate { $0.workoutSetID == setID }
            ))) ?? []
        }
        let analyses = performances.flatMap { performance in
            let performanceID = performance.id
            return (try? context.fetch(FetchDescriptor<PerformanceAnalysis>(
                predicate: #Predicate { $0.performanceID == performanceID }
            ))) ?? []
        }
        let linkedWorkouts = try context.fetch(FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.sourceWorkoutSessionID == sessionID }
        ))
        let projectedWorkouts = linkedWorkouts.filter {
            $0.projectionKey?.hasPrefix("guided-performance:") == true
        }
        let sourceWorkouts = linkedWorkouts.filter {
            $0.projectionKey?.hasPrefix("guided-performance:") != true
        }
        let mediaPaths = Set(
            sets.compactMap(\.recordedVideoPath)
                + efforts.compactMap(\.recordedVideoPath)
                + performances.compactMap(\.activeVideoPath)
                + analyses.map(\.sourceMediaPath).filter { !$0.isEmpty }
                + projectedWorkouts.flatMap(\.mediaAttachments).map(\.path)
        )

        analyses.forEach(context.delete)
        projectedWorkouts.forEach(context.delete)
        for workout in sourceWorkouts {
            workout.sourceWorkoutSessionID = nil
            workout.sourcePerformanceID = nil
            workout.sourcePerformance = nil
        }
        efforts.forEach(context.delete)
        sets.forEach(context.delete)
        performances.forEach(context.delete)
        context.delete(session)
        try context.save()
        mediaPaths.forEach { _ = MediaStore.removeStoredFile(at: $0) }
    }

    static func archive(
        _ program: TrainingProgram,
        in context: ModelContext
    ) throws {
        program.status = .archived
        try context.save()
    }

    static func unarchive(
        _ program: TrainingProgram,
        in context: ModelContext
    ) throws {
        program.status = .active
        try context.save()
    }

    static func deleteProgram(
        _ program: TrainingProgram,
        in context: ModelContext
    ) throws {
        let programID = program.id
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.programID == programID }
        ))
        for session in sessions {
            let snapshot = session.programNameSnapshot?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if snapshot == nil || snapshot?.isEmpty == true {
                session.programNameSnapshot = program.name
            }
        }
        let exercises = templateExercises(for: program, in: context)
        let setPrescriptions = exercises.flatMap { exercise in
            guard exercise.setPrescriptions.isEmpty else {
                return exercise.setPrescriptions
            }
            let exerciseID = exercise.id
            return (try? context.fetch(
                FetchDescriptor<TemplateSetPrescription>(
                    predicate: #Predicate {
                        $0.templateExerciseID == exerciseID
                    }
                )
            )) ?? []
        }
        setPrescriptions.forEach { context.delete($0) }
        exercises.forEach { context.delete($0) }
        context.delete(program)
        try context.save()
    }

    @discardableResult
    static func backfillProgramSource(
        for session: WorkoutSession,
        programs: [TrainingProgram] = [],
        in context: ModelContext? = nil
    ) -> Bool {
        let resolved = resolveProgramSource(
            for: session,
            programs: programs,
            in: context
        )
        guard let resolved else { return false }
        var changed = false
        if session.programID == nil {
            session.programID = resolved.programID
            changed = true
        }
        let snapshot = session.programNameSnapshot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if snapshot == nil || snapshot?.isEmpty == true {
            session.programNameSnapshot = resolved.name
            changed = true
        }
        return changed
    }

    /// Resolves a display label for a historical session's source plan.
    static func programSourceLabel(
        for session: WorkoutSession,
        programs: [TrainingProgram] = [],
        in context: ModelContext? = nil
    ) -> String? {
        guard let resolved = resolveProgramSource(
            for: session,
            programs: programs,
            in: context
        ) else {
            return nil
        }
        return resolved.name
    }

    private struct ResolvedProgramSource {
        var programID: UUID?
        var name: String
    }

    private static func resolveProgramSource(
        for session: WorkoutSession,
        programs: [TrainingProgram],
        in context: ModelContext?
    ) -> ResolvedProgramSource? {
        let snapshot = session.programNameSnapshot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let snapshot, !snapshot.isEmpty {
            return ResolvedProgramSource(
                programID: session.programID,
                name: snapshot
            )
        }

        let resolvedPrograms: [TrainingProgram]
        if let context, let programID = session.programID {
            var descriptor = FetchDescriptor<TrainingProgram>(
                predicate: #Predicate { $0.id == programID }
            )
            descriptor.fetchLimit = 1
            resolvedPrograms = (try? context.fetch(descriptor)) ?? programs
        } else if let context {
            // Current sessions always carry id/name snapshots. This whole-catalog
            // fallback only remains for a pre-baseline row missing both fields.
            resolvedPrograms =
                (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? programs
        } else {
            resolvedPrograms = programs
        }

        if let programID = session.programID,
           let program = resolvedPrograms.first(where: { $0.id == programID })
        {
            return ResolvedProgramSource(
                programID: program.id,
                name: program.name
            )
        }

        // Legacy rows without a source id can still be matched against one current plan.
        guard let context else { return nil }
        let fingerprint = prescriptionFingerprint(session.prescriptionSnapshot)
        guard !fingerprint.isEmpty else { return nil }
        var matches: [TrainingProgram] = []
        for program in resolvedPrograms {
            let values = prescriptions(for: program, in: context)
            guard prescriptionFingerprint(values) == fingerprint else {
                continue
            }
            matches.append(program)
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return ResolvedProgramSource(
            programID: match.id,
            name: match.name
        )
    }

    /// Keep each conversion tiny — CI's x86_64 type checker times out on chained
    /// sorted/map and mixed optional array literals in these fingerprints.
    private static func prescriptionFingerprint(
        _ prescriptions: [TemplateExercisePrescription]
    ) -> String {
        let ordered = prescriptions.sorted { left, right in
            left.order < right.order
        }
        var fields: [String] = []
        fields.reserveCapacity(ordered.count)
        for prescription in ordered {
            fields.append(exercisePrescriptionFingerprint(prescription))
        }
        return fields.joined(separator: "|")
    }

    private static func exercisePrescriptionFingerprint(
        _ prescription: TemplateExercisePrescription
    ) -> String {
        let orderedSets = prescription.plannedSets.sorted { left, right in
            left.order < right.order
        }
        var setFields: [String] = []
        setFields.reserveCapacity(orderedSets.count)
        for plannedSet in orderedSets {
            setFields.append(setPrescriptionFingerprint(plannedSet))
        }
        let targetSets: Int = prescription.targetSets ?? -1
        let targetReps: Int = prescription.targetReps ?? -1
        let targetWeightKG: Double = prescription.targetWeightKG ?? -1
        let targetRestSeconds: Int = prescription.targetRestSeconds ?? -1
        let restBetweenSidesSeconds: Int = prescription.restBetweenSidesSeconds ?? -1
        let warmup: String = prescription.firstSetIsWarmup ? "1" : "0"
        var parts: [String] = []
        parts.append(prescription.exerciseID.uuidString)
        parts.append(String(targetSets))
        parts.append(String(targetReps))
        parts.append(String(targetWeightKG))
        parts.append(String(targetRestSeconds))
        parts.append(String(restBetweenSidesSeconds))
        parts.append(warmup)
        parts.append(prescription.laterality.rawValue)
        parts.append(setFields.joined(separator: ","))
        return parts.joined(separator: ":")
    }

    private static func setPrescriptionFingerprint(
        _ set: TemplateSetPrescriptionValue
    ) -> String {
        let targetReps: Int = set.targetReps ?? -1
        let targetDurationSeconds: Int = set.targetDurationSeconds ?? -1
        let targetWeightKG: Double = set.targetWeightKG ?? -1
        let leftWeightKG: Double = set.leftWeightKG ?? -1
        let rightWeightKG: Double = set.rightWeightKG ?? -1
        let restBetweenSidesSeconds: Int = set.restBetweenSidesSeconds ?? -1
        let restAfterSetSeconds: Int = set.restAfterSetSeconds ?? -1
        var parts: [String] = []
        parts.append(String(set.order))
        parts.append(set.kind.rawValue)
        parts.append(set.targetKind.rawValue)
        parts.append(String(targetReps))
        parts.append(String(targetDurationSeconds))
        parts.append(String(targetWeightKG))
        parts.append(String(leftWeightKG))
        parts.append(String(rightWeightKG))
        parts.append(String(restBetweenSidesSeconds))
        parts.append(String(restAfterSetSeconds))
        parts.append(set.notes)
        return parts.joined(separator: "/")
    }

    private static func insert(
        _ prescriptions: [TemplateExercisePrescription],
        program: TrainingProgram,
        in context: ModelContext
    ) {
        let definitions = definitions(
            for: Set(prescriptions.map(\.exerciseID)),
            in: context
        )
        for prescription in prescriptions {
            let definition = definitions[prescription.exerciseID]
            if let definition {
                ExerciseLoggingProfile.adoptIfUnset(
                    definition,
                    laterality: prescription.laterality,
                    targetKind: prescription.plannedSets.first?.targetKind
                )
            }
            let item = TemplateExercise(
                id: prescription.id,
                prescriptionGroupID: program.prescriptionGroupID ?? program.id,
                exerciseID: prescription.exerciseID,
                order: prescription.order,
                targetSets: prescription.targetSets,
                targetReps: prescription.targetReps,
                targetWeightKG: prescription.targetWeightKG,
                targetRestSeconds: prescription.targetRestSeconds,
                restBetweenSidesSeconds: prescription.restBetweenSidesSeconds,
                firstSetIsWarmup: prescription.firstSetIsWarmup,
                equipmentKind: prescription.equipmentKind,
                notes: prescription.notes,
                laterality: prescription.laterality
            )
            item.program = program
            context.insert(item)
            item.exerciseDefinition = definition
            for value in prescription.plannedSets {
                let set = TemplateSetPrescription(
                    templateExerciseID: item.id,
                    value: value
                )
                set.templateExercise = item
                context.insert(set)
            }
        }
    }
}

private extension TrainingPlanStore {
    private static func validate(
        _ values: [TemplateExercisePrescription],
        in context: ModelContext
    ) throws {
        guard !values.isEmpty else { throw TrainingPlanError.emptyTemplate }
        let definitions = definitions(
            for: Set(values.map(\.exerciseID)),
            in: context
        )
        let activeIDs = Set(definitions.values.filter { !$0.isArchived }.map(\.id))
        var orders = Set<Int>()
        for value in values {
            try validatePrescription(
                value,
                activeExerciseIDs: activeIDs,
                orders: &orders
            )
        }
    }

    private static func validatePrescription(
        _ value: TemplateExercisePrescription,
        activeExerciseIDs: Set<UUID>,
        orders: inout Set<Int>
    ) throws {
        guard activeExerciseIDs.contains(value.exerciseID) else {
            throw TrainingPlanError.missingExercise(value.exerciseID)
        }
        guard orders.insert(value.order).inserted else {
            throw TrainingPlanError.duplicateOrder(value.order)
        }
        if let sets = value.targetSets, !(1 ... 100).contains(sets) {
            throw TrainingPlanError.invalidSets
        }
        if let reps = value.targetReps, !(1 ... 1000).contains(reps) {
            throw TrainingPlanError.invalidValue("目标次数")
        }
        if let weight = value.targetWeightKG, !(0 ... 1000).contains(weight) {
            throw TrainingPlanError.invalidValue("目标重量")
        }
        if let rest = value.targetRestSeconds, !(0 ... 3600).contains(rest) {
            throw TrainingPlanError.invalidValue("目标间歇")
        }
        if let rest = value.restBetweenSidesSeconds,
           !(0 ... 3600).contains(rest)
        {
            throw TrainingPlanError.invalidValue("换侧间歇")
        }
        if value.laterality != .both, value.restBetweenSidesSeconds != nil {
            throw TrainingPlanError.invalidValue("只有左右分开动作可以设置换侧间歇")
        }
        guard !value.plannedSets.isEmpty else {
            throw TrainingPlanError.invalidValue("目标次数")
        }
        var setOrders = Set<Int>()
        for set in value.plannedSets {
            try validateSet(
                set,
                laterality: value.laterality,
                orders: &setOrders
            )
        }
    }

    private static func validateSet(
        _ set: TemplateSetPrescriptionValue,
        laterality: ExerciseLaterality,
        orders: inout Set<Int>
    ) throws {
        guard orders.insert(set.order).inserted,
              (1 ... 100).contains(set.order)
        else {
            throw TrainingPlanError.invalidValue("组顺序")
        }
        switch set.targetKind {
        case .repetitions:
            guard set.targetDurationSeconds == nil else {
                throw TrainingPlanError.invalidValue("按次数组不能设置时长")
            }
            guard let reps = set.targetReps,
                  (1 ... 1000).contains(reps)
            else {
                throw TrainingPlanError.invalidValue("目标次数")
            }
        case .duration:
            guard set.targetReps == nil else {
                throw TrainingPlanError.invalidValue("按时长组不能设置次数")
            }
            guard let duration = set.targetDurationSeconds,
                  (1 ... 86400).contains(duration)
            else {
                throw TrainingPlanError.invalidValue("目标时长")
            }
        }
        for weight in [
            set.targetWeightKG,
            set.leftWeightKG,
            set.rightWeightKG
        ].compactMap({ $0 }) where !(0 ... 1000).contains(weight) {
            throw TrainingPlanError.invalidValue("目标重量")
        }
        let hasInvalidSideWeight = switch laterality {
        case .none:
            set.leftWeightKG != nil || set.rightWeightKG != nil
        case .left:
            set.rightWeightKG != nil
        case .right:
            set.leftWeightKG != nil
        case .both:
            false
        }
        if hasInvalidSideWeight {
            throw TrainingPlanError.invalidValue("逐侧重量")
        }
    }

    private static func issue(
        _ id: String,
        _ severity: TrainingReadinessIssue.Severity,
        _ message: String
    ) -> TrainingReadinessIssue {
        TrainingReadinessIssue(id: id, severity: severity, message: message)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
