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
        let existingIDs = Set(existing.map(\.id))
        let sets = try context.fetch(FetchDescriptor<TemplateSetPrescription>())
            .filter { existingIDs.contains($0.templateExerciseID) }
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
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        let names = Dictionary(uniqueKeysWithValues: definitions.map {
            ($0.id, $0.canonicalName)
        })
        let setModels = (
            try? context.fetch(FetchDescriptor<TemplateSetPrescription>())
        ) ?? []
        return exercises.map { exercise in
            let relatedSets = exercise.setPrescriptions
            let plannedSets = (relatedSets.isEmpty
                ? setModels.filter { $0.templateExerciseID == exercise.id }
                : relatedSets)
                .sorted { $0.order < $1.order }
                .map(\.value)
            return TemplateExercisePrescription(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                exerciseName: names[exercise.exerciseID] ?? "已删除动作",
                order: exercise.order,
                targetSets: exercise.targetSets,
                targetReps: exercise.targetReps,
                targetWeightKG: exercise.targetWeightKG,
                targetRestSeconds: exercise.targetRestSeconds,
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
        return (try? context.fetch(FetchDescriptor<TemplateExercise>()))?
            .filter { $0.prescriptionGroupID == groupID } ?? []
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
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        let activeIDs = Set(definitions.filter { !$0.isArchived }.map(\.id))
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
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
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
            performance.exerciseDefinition = definitions.first(where: {
                $0.id == prescription.exerciseID
            })
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
            for planned in prescription.plannedSets.sorted(by: { $0.order < $1.order }) {
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
                    plannedRestSeconds: planned.restAfterSetSeconds,
                    restBetweenSidesSeconds: planned.restBetweenSidesSeconds
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
        let session = (
            try? context.fetch(FetchDescriptor<WorkoutSession>())
        )?.first { $0.id == sessionID }
        let relatedPerformances = session?.performances ?? []
        let performances = relatedPerformances.isEmpty
            ? ((try? context.fetch(FetchDescriptor<ExercisePerformance>()))?
                .filter { $0.sessionID == sessionID } ?? [])
            : relatedPerformances
        let performanceIDs = Set(performances.map(\.id))
        let sets = (
            try? context.fetch(FetchDescriptor<WorkoutSet>())
        )?.filter { performanceIDs.contains($0.performanceID) } ?? []
        let setIDs = Set(sets.map(\.id))
        let efforts = (
            try? context.fetch(FetchDescriptor<WorkoutEffort>())
        )?.filter { setIDs.contains($0.workoutSetID) } ?? []
        let allProjectedWorkouts = (
            try? context.fetch(FetchDescriptor<WorkoutEntry>())
        ) ?? []
        let workoutsByProjectionKey = Dictionary(grouping: allProjectedWorkouts) {
            $0.projectionKey
        }.reduce(into: [String: WorkoutEntry]()) { result, element in
            let (key, candidates) = element
            guard let key, candidates.count == 1,
                  let candidate = candidates.first
            else { return }
            result[key] = candidate
        }
        let workoutsByPerformanceID = performances.reduce(
            into: [UUID: WorkoutEntry]()
        ) { result, performance in
            guard !performance.workoutProjectionSuppressed else { return }
            let key = SomaDataMigration.projectionKey(for: performance.id)
            if let related = performance.projectedWorkout,
               related.projectionKey == key
            {
                result[performance.id] = related
            } else if let keyed = workoutsByProjectionKey[key] {
                result[performance.id] = keyed
            }
        }
        let projectedWorkouts = Array(workoutsByPerformanceID.values)
        let summaryEnd = session?.endedAt
            ?? sets.compactMap(\.completedAt).max()
            ?? session?.startedAt
            ?? .now
        let mediaPaths = Set(
            sets.compactMap(\.recordedVideoPath)
                + efforts.compactMap(\.recordedVideoPath)
                + performances.compactMap(\.activeVideoPath)
                + projectedWorkouts.flatMap(\.mediaAttachments).map(\.path)
        )
        let exerciseSummaries = performances
            .sorted { $0.order < $1.order }
            .map { performance in
                let performanceSets = sets.filter {
                    $0.performanceID == performance.id
                }
                let projectedWorkout = workoutsByPerformanceID[performance.id]
                let performanceSetIDs = Set(performanceSets.map(\.id))
                let performanceEfforts = efforts.filter {
                    performanceSetIDs.contains($0.workoutSetID)
                }
                return TrainingExerciseSummary(
                    id: performance.id,
                    name: performance.exerciseName,
                    completedSets: performanceSets.count {
                        $0.status == .completed
                    },
                    partialSets: performanceSets.count {
                        $0.status == .partial
                    },
                    skippedSets: performanceSets.count {
                        $0.status == .skipped
                    },
                    failedSets: performanceSets.count {
                        $0.status == .failed
                    },
                    completedVolume: performance.workoutProjectionSuppressed
                        ? 0
                        : projectedWorkout?.estimatedVolume
                        ?? completedVolume(
                            sets: performanceSets,
                            efforts: performanceEfforts
                        )
                )
            }
        let caloriePerformanceIDs = Set(exerciseSummaries.filter {
            $0.completedSets > 0 || $0.partialSets > 0
        }.map(\.id))
        let calorieValues = caloriePerformanceIDs.compactMap {
            workoutsByPerformanceID[$0]?.estimatedCalories
        }
        let sessionCalories = !caloriePerformanceIDs.isEmpty
            && calorieValues.count == caloriePerformanceIDs.count
            ? calorieValues.reduce(0, +)
            : nil
        return TrainingSessionSummary(
            completedSets: exerciseSummaries.reduce(0) { $0 + $1.completedSets },
            partialSets: exerciseSummaries.reduce(0) { $0 + $1.partialSets },
            skippedSets: sets.count { $0.status == .skipped },
            failedSets: sets.count { $0.status == .failed },
            completedVolume: exerciseSummaries.reduce(0) { $0 + $1.completedVolume },
            exerciseCount: exerciseSummaries.count {
                $0.completedSets > 0 || $0.partialSets > 0
            },
            durationSeconds: max(
                Int(summaryEnd.timeIntervalSince(session?.startedAt ?? summaryEnd)),
                0
            ),
            recordedVideoCount: mediaPaths.count,
            estimatedCalories: sessionCalories,
            exercises: exerciseSummaries
        )
    }

    static func deleteSession(
        _ session: WorkoutSession,
        in context: ModelContext
    ) throws {
        let performances = try context.fetch(
            FetchDescriptor<ExercisePerformance>()
        ).filter { $0.sessionID == session.id }
        let performanceIDs = Set(performances.map(\.id))
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            .filter { performanceIDs.contains($0.performanceID) }
        let setIDs = Set(sets.map(\.id))
        let efforts = try context.fetch(FetchDescriptor<WorkoutEffort>())
            .filter { setIDs.contains($0.workoutSetID) }
        let analyses = try context.fetch(FetchDescriptor<PerformanceAnalysis>())
            .filter { performanceIDs.contains($0.performanceID) }
        let projectedWorkouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
            .filter { $0.sourceWorkoutSessionID == session.id }
        let mediaPaths = Set(
            sets.compactMap(\.recordedVideoPath)
                + efforts.compactMap(\.recordedVideoPath)
                + performances.compactMap(\.activeVideoPath)
                + analyses.map(\.sourceMediaPath).filter { !$0.isEmpty }
                + projectedWorkouts.flatMap(\.mediaAttachments).map(\.path)
        )

        analyses.forEach(context.delete)
        projectedWorkouts.forEach(context.delete)
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
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.programID == program.id }
        for session in sessions {
            let snapshot = session.programNameSnapshot?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if snapshot == nil || snapshot?.isEmpty == true {
                session.programNameSnapshot = program.name
            }
        }
        let exercises = templateExercises(for: program, in: context)
        let exerciseIDs = Set(exercises.map(\.id))
        let setPrescriptions = try context.fetch(
            FetchDescriptor<TemplateSetPrescription>()
        ).filter { exerciseIDs.contains($0.templateExerciseID) }
        setPrescriptions.forEach { context.delete($0) }
        exercises.forEach { context.delete($0) }
        context.delete(program)
        try context.save()
    }

    /// Persists plan id/name onto sessions that can be matched by their frozen prescription.
    @discardableResult
    static func backfillProgramSources(in context: ModelContext) -> Int {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        var changed = 0
        for session in sessions where backfillProgramSource(
            for: session,
            programs: programs,
            in: context
        ) {
            changed += 1
        }
        if changed > 0 {
            try? context.save()
        }
        return changed
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

        let resolvedPrograms: [TrainingProgram] = if let context {
            (try? context.fetch(FetchDescriptor<TrainingProgram>()))
                ?? programs
        } else {
            programs
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
        let warmup: String = prescription.firstSetIsWarmup ? "1" : "0"
        var parts: [String] = []
        parts.append(prescription.exerciseID.uuidString)
        parts.append(String(targetSets))
        parts.append(String(targetReps))
        parts.append(String(targetWeightKG))
        parts.append(String(targetRestSeconds))
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
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        for prescription in prescriptions {
            let definition = definitions.first(where: {
                $0.id == prescription.exerciseID
            })
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
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let activeIDs = Set(definitions.filter { !$0.isArchived }.map(\.id))
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
        for rest in [
            set.restBetweenSidesSeconds,
            set.restAfterSetSeconds
        ].compactMap({ $0 }) where !(0 ... 3600).contains(rest) {
            throw TrainingPlanError.invalidValue("目标间歇")
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

    private static func completedVolume(
        sets: [WorkoutSet],
        efforts: [WorkoutEffort]
    ) -> Double {
        let effortVolume = efforts.compactMap(\.completedVolume).reduce(0, +)
        let hasCompletedEffort = efforts.contains { $0.status == .completed }
        return hasCompletedEffort
            ? effortVolume
            : sets.compactMap(\.completedVolume).reduce(0, +)
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
