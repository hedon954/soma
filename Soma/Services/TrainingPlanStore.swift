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
    var skippedSets: Int
    var completedVolume: Double
    var exerciseCount: Int
    var durationSeconds: Int
    var recordedVideoCount: Int
    var exercises: [TrainingExerciseSummary]

    var text: String {
        var values = [
            "完成 \(exerciseCount) 个动作",
            "\(completedSets) 组"
        ]
        if skippedSets > 0 {
            values.append("跳过 \(skippedSets) 组")
        }
        if completedVolume > 0 {
            values.append(
                "有效容量 \(completedVolume.formatted(.number.precision(.fractionLength(0 ... 1)))) kg"
            )
        }
        if recordedVideoCount > 0 {
            values.append("录制 \(recordedVideoCount) 组")
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
    var skippedSets: Int
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
        templateName: String,
        scheduleHint: String = "",
        prescriptions: [TemplateExercisePrescription],
        source: String = "user",
        in context: ModelContext
    ) throws -> TrainingProgram {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw TrainingPlanError.emptyName }
        try validate(prescriptions, in: context)

        let program = TrainingProgram(name: normalizedName, goal: goal)
        let initialChange = TemplateVersionDiff.changeLog(
            from: nil,
            to: prescriptions
        )
        let version = WorkoutTemplateVersion(
            programID: program.id,
            version: 1,
            name: templateName,
            scheduleHint: scheduleHint,
            source: source,
            changeSummary: initialChange.summary,
            changeDetails: initialChange.details
        )
        program.currentTemplateVersionID = version.id
        context.insert(program)
        context.insert(version)
        insert(prescriptions, templateVersionID: version.id, in: context)
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
        return program
    }

    static func createNextVersion(
        for program: TrainingProgram,
        name: String,
        scheduleHint: String,
        prescriptions: [TemplateExercisePrescription],
        source: String = "user",
        in context: ModelContext
    ) throws -> WorkoutTemplateVersion {
        try validate(prescriptions, in: context)
        let versions = try context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
            .filter { $0.programID == program.id }
        let prior = versions.max { $0.version < $1.version }
        let previousPrescriptions = prior.map {
            Self.prescriptions(for: $0, in: context)
        }
        let changeLog = TemplateVersionDiff.changeLog(
            from: previousPrescriptions,
            to: prescriptions
        )
        let version = WorkoutTemplateVersion(
            programID: program.id,
            familyID: prior?.familyID ?? UUID(),
            version: (prior?.version ?? 0) + 1,
            name: name,
            scheduleHint: scheduleHint,
            source: source,
            changeSummary: changeLog.summary,
            changeDetails: changeLog.details
        )
        context.insert(version)
        insert(prescriptions, templateVersionID: version.id, in: context)
        program.currentTemplateVersionID = version.id
        program.updatedAt = .now
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
        return version
    }

    static func prescriptions(
        for version: WorkoutTemplateVersion,
        in context: ModelContext
    ) -> [TemplateExercisePrescription] {
        let exercises = (
            try? context.fetch(FetchDescriptor<TemplateExercise>())
        )?.filter { $0.templateVersionID == version.id }
            .sorted { $0.order < $1.order } ?? []
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        let names = Dictionary(uniqueKeysWithValues: definitions.map {
            ($0.id, $0.canonicalName)
        })
        return exercises.map {
            TemplateExercisePrescription(
                id: $0.id,
                exerciseID: $0.exerciseID,
                exerciseName: names[$0.exerciseID] ?? "已删除动作",
                order: $0.order,
                targetSets: $0.targetSets,
                targetReps: $0.targetReps,
                targetWeightKG: $0.targetWeightKG,
                targetRestSeconds: $0.targetRestSeconds,
                firstSetIsWarmup: $0.firstSetIsWarmup,
                equipmentKind: $0.equipmentKind,
                notes: $0.notes
            )
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
            if autoRecordingPolicy == .enabled,
               prescription.firstSetIsWarmup,
               (prescription.targetSets ?? 0) < 2
            {
                issues.append(issue(
                    "recording-\(prescription.id)",
                    .warning,
                    "“\(prescription.exerciseName)”没有第 2 组，无法自动录制工作组。"
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
        guard let versionID = program.currentTemplateVersionID,
              let version = try context.fetch(
                  FetchDescriptor<WorkoutTemplateVersion>()
              ).first(where: { $0.id == versionID })
        else {
            throw TrainingPlanError.missingTemplate
        }
        let values = prescriptions(for: version, in: context)
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
            sourceTemplateFamilyID: version.familyID,
            sourceTemplateVersion: version.version,
            prescriptionSnapshot: values,
            status: .active,
            autoRecordingPolicy: autoRecordingPolicy
        )
        context.insert(session)
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())

        for prescription in values.sorted(by: { $0.order < $1.order }) {
            let performance = ExercisePerformance(
                sessionID: session.id,
                exerciseID: prescription.exerciseID,
                exerciseName: prescription.exerciseName,
                order: prescription.order,
                prescriptionSnapshot: prescription
            )
            context.insert(performance)
            performance.exerciseDefinition = definitions.first(where: {
                $0.id == prescription.exerciseID
            })
            let setCount = prescription.targetSets ?? 0
            for index in 0 ..< setCount {
                context.insert(WorkoutSet(
                    performanceID: performance.id,
                    order: index + 1,
                    kind: prescription.firstSetIsWarmup && index == 0
                        ? .warmup
                        : .working,
                    plannedReps: prescription.targetReps,
                    plannedWeightKG: prescription.targetWeightKG,
                    plannedRestSeconds: prescription.targetRestSeconds
                ))
            }
        }
        if let first = try context.fetch(FetchDescriptor<ExercisePerformance>())
            .filter({ $0.sessionID == session.id })
            .min(by: { $0.order < $1.order })
        {
            session.currentPerformanceID = first.id
        }
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
        let performances = (
            try? context.fetch(FetchDescriptor<ExercisePerformance>())
        )?.filter { $0.sessionID == sessionID } ?? []
        let performanceIDs = Set(performances.map(\.id))
        let sets = (
            try? context.fetch(FetchDescriptor<WorkoutSet>())
        )?.filter { performanceIDs.contains($0.performanceID) } ?? []
        let session = (
            try? context.fetch(FetchDescriptor<WorkoutSession>())
        )?.first { $0.id == sessionID }
        let projectedWorkouts = (
            try? context.fetch(FetchDescriptor<WorkoutEntry>())
        )?.filter { $0.sourceWorkoutSessionID == sessionID } ?? []
        let workoutsByPerformanceID = projectedWorkouts.reduce(
            into: [UUID: WorkoutEntry]()
        ) { result, workout in
            if let performanceID = workout.sourcePerformanceID,
               result[performanceID] == nil
            {
                result[performanceID] = workout
            }
        }
        let summaryEnd = session?.endedAt
            ?? sets.compactMap(\.completedAt).max()
            ?? session?.startedAt
            ?? .now
        let mediaPaths = Set(
            sets.compactMap(\.recordedVideoPath)
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
                return TrainingExerciseSummary(
                    id: performance.id,
                    name: performance.exerciseName,
                    completedSets: projectedWorkout?.setEntries.count
                        ?? performanceSets.count { $0.status == .completed },
                    skippedSets: performanceSets.count {
                        $0.status == .skipped
                    },
                    completedVolume: projectedWorkout?.estimatedVolume
                        ?? performanceSets.compactMap(\.completedVolume).reduce(0, +)
                )
            }
        return TrainingSessionSummary(
            completedSets: exerciseSummaries.reduce(0) { $0 + $1.completedSets },
            skippedSets: sets.count { $0.status == .skipped },
            completedVolume: exerciseSummaries.reduce(0) { $0 + $1.completedVolume },
            exerciseCount: exerciseSummaries.count { $0.completedSets > 0 },
            durationSeconds: max(
                Int(summaryEnd.timeIntervalSince(session?.startedAt ?? summaryEnd)),
                0
            ),
            recordedVideoCount: mediaPaths.count,
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
        let analyses = try context.fetch(FetchDescriptor<PerformanceAnalysis>())
            .filter { performanceIDs.contains($0.performanceID) }
        let projectedWorkouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
            .filter { $0.sourceWorkoutSessionID == session.id }
        let mediaPaths = Set(
            sets.compactMap(\.recordedVideoPath)
                + performances.compactMap(\.activeVideoPath)
                + analyses.map(\.sourceMediaPath).filter { !$0.isEmpty }
                + projectedWorkouts.flatMap(\.mediaAttachments).map(\.path)
        )

        analyses.forEach(context.delete)
        projectedWorkouts.forEach(context.delete)
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
        let versions = try context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
            .filter { $0.programID == program.id }
        let familyIDs = Set(versions.map(\.familyID))
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter {
                $0.programID == program.id
                    || ($0.sourceTemplateFamilyID.map(familyIDs.contains) ?? false)
            }
        for session in sessions {
            if session.programID == nil {
                session.programID = program.id
            }
            let snapshot = session.programNameSnapshot?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if snapshot == nil || snapshot?.isEmpty == true {
                session.programNameSnapshot = program.name
            }
        }
        let versionIDs = Set(versions.map(\.id))
        let exercises = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { versionIDs.contains($0.templateVersionID) }
        exercises.forEach { context.delete($0) }
        versions.forEach { context.delete($0) }
        context.delete(program)
        try context.save()
    }

    /// Persists plan id/name onto sessions that still only have a template family link.
    @discardableResult
    static func backfillProgramSources(in context: ModelContext) -> Int {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        let versions = (try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>()))
            ?? []
        var changed = 0
        for session in sessions where backfillProgramSource(
            for: session,
            programs: programs,
            versions: versions
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
        versions: [WorkoutTemplateVersion] = [],
        in context: ModelContext? = nil
    ) -> Bool {
        let resolved = resolveProgramSource(
            for: session,
            programs: programs,
            versions: versions,
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
        versions: [WorkoutTemplateVersion] = [],
        in context: ModelContext? = nil
    ) -> String? {
        guard let resolved = resolveProgramSource(
            for: session,
            programs: programs,
            versions: versions,
            in: context
        ) else {
            return nil
        }
        if let version = resolved.version {
            return "\(resolved.name) · v\(version)"
        }
        return resolved.name
    }

    private struct ResolvedProgramSource {
        var programID: UUID?
        var name: String
        var version: Int?
    }

    private static func resolveProgramSource(
        for session: WorkoutSession,
        programs: [TrainingProgram],
        versions: [WorkoutTemplateVersion],
        in context: ModelContext?
    ) -> ResolvedProgramSource? {
        let snapshot = session.programNameSnapshot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let snapshot, !snapshot.isEmpty {
            return ResolvedProgramSource(
                programID: session.programID,
                name: snapshot,
                version: session.sourceTemplateVersion
            )
        }

        let resolvedPrograms: [TrainingProgram]
        let resolvedVersions: [WorkoutTemplateVersion]
        if let context {
            resolvedPrograms = (try? context.fetch(FetchDescriptor<TrainingProgram>()))
                ?? programs
            resolvedVersions = (try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>()))
                ?? versions
        } else {
            resolvedPrograms = programs
            resolvedVersions = versions
        }

        if let programID = session.programID,
           let program = resolvedPrograms.first(where: { $0.id == programID })
        {
            return ResolvedProgramSource(
                programID: program.id,
                name: program.name,
                version: session.sourceTemplateVersion
            )
        }

        if let familyID = session.sourceTemplateFamilyID {
            let exactVersion = resolvedVersions.first(where: {
                $0.familyID == familyID
                    && (
                        session.sourceTemplateVersion == nil
                            || $0.version == session.sourceTemplateVersion
                    )
            })
            let matchedVersion = exactVersion
                ?? resolvedVersions.first(where: { $0.familyID == familyID })
            if let matchedVersion,
               let program = resolvedPrograms.first(where: {
                   $0.id == matchedVersion.programID
               })
            {
                return ResolvedProgramSource(
                    programID: program.id,
                    name: program.name,
                    version: session.sourceTemplateVersion ?? matchedVersion.version
                )
            }
        }

        // Last resort for legacy rows that lost template family links: match the
        // frozen prescription fingerprint against a unique surviving template.
        guard let context else { return nil }
        let fingerprint = prescriptionFingerprint(session.prescriptionSnapshot)
        guard !fingerprint.isEmpty else { return nil }
        let matches: [(TrainingProgram, WorkoutTemplateVersion)] = resolvedVersions
            .compactMap { version in
                guard let program = resolvedPrograms.first(where: {
                    $0.id == version.programID
                }) else {
                    return nil
                }
                let values = prescriptions(for: version, in: context)
                guard prescriptionFingerprint(values) == fingerprint else {
                    return nil
                }
                return (program, version)
            }
        let uniquePrograms = Dictionary(grouping: matches, by: { $0.0.id })
        guard uniquePrograms.count == 1,
              let match = matches.first
        else {
            return nil
        }
        return ResolvedProgramSource(
            programID: match.0.id,
            name: match.0.name,
            version: session.sourceTemplateVersion ?? match.1.version
        )
    }

    private static func prescriptionFingerprint(
        _ prescriptions: [TemplateExercisePrescription]
    ) -> String {
        prescriptions
            .sorted { $0.order < $1.order }
            .map {
                [
                    $0.exerciseID.uuidString,
                    String($0.targetSets ?? -1),
                    String($0.targetReps ?? -1),
                    String($0.targetWeightKG ?? -1),
                    String($0.targetRestSeconds ?? -1),
                    $0.firstSetIsWarmup ? "1" : "0"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    static func resolvedChangeLog(
        for version: WorkoutTemplateVersion,
        previous: WorkoutTemplateVersion?,
        in context: ModelContext
    ) -> TemplateVersionChangeLog {
        if let summary = version.changeSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !summary.isEmpty
        {
            return TemplateVersionChangeLog(
                summary: summary,
                details: version.changeDetails?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                    ?? summary
            )
        }
        let current = prescriptions(for: version, in: context)
        let prior = previous.map { prescriptions(for: $0, in: context) }
        return TemplateVersionDiff.changeLog(from: prior, to: current)
    }

    private static func insert(
        _ prescriptions: [TemplateExercisePrescription],
        templateVersionID: UUID,
        in context: ModelContext
    ) {
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        for prescription in prescriptions {
            let item = TemplateExercise(
                id: prescription.id,
                templateVersionID: templateVersionID,
                exerciseID: prescription.exerciseID,
                order: prescription.order,
                targetSets: prescription.targetSets,
                targetReps: prescription.targetReps,
                targetWeightKG: prescription.targetWeightKG,
                targetRestSeconds: prescription.targetRestSeconds,
                firstSetIsWarmup: prescription.firstSetIsWarmup,
                equipmentKind: prescription.equipmentKind,
                notes: prescription.notes
            )
            context.insert(item)
            item.exerciseDefinition = definitions.first(where: {
                $0.id == prescription.exerciseID
            })
        }
    }

    private static func validate(
        _ values: [TemplateExercisePrescription],
        in context: ModelContext
    ) throws {
        guard !values.isEmpty else { throw TrainingPlanError.emptyTemplate }
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let activeIDs = Set(definitions.filter { !$0.isArchived }.map(\.id))
        var orders = Set<Int>()
        for value in values {
            guard activeIDs.contains(value.exerciseID) else {
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
