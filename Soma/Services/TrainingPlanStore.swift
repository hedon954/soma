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
        return values.joined(separator: "，") + "。"
    }
}

@MainActor
enum TrainingPlanStore {
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
        let version = WorkoutTemplateVersion(
            programID: program.id,
            version: 1,
            name: templateName,
            scheduleHint: scheduleHint,
            source: source
        )
        program.currentTemplateVersionID = version.id
        context.insert(program)
        context.insert(version)
        insert(prescriptions, templateVersionID: version.id, in: context)
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
        let version = WorkoutTemplateVersion(
            programID: program.id,
            familyID: prior?.familyID ?? UUID(),
            version: (prior?.version ?? 0) + 1,
            name: name,
            scheduleHint: scheduleHint,
            source: source
        )
        context.insert(version)
        insert(prescriptions, templateVersionID: version.id, in: context)
        program.currentTemplateVersionID = version.id
        program.updatedAt = .now
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
            if autoRecording,
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
        autoRecording: Bool = false,
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
            autoRecording: autoRecording,
            in: context
        ).contains { $0.severity == .blocking }
        guard !blocking else { throw TrainingPlanError.emptyTemplate }

        let session = WorkoutSession(
            gymID: gymID,
            sourceTemplateFamilyID: version.familyID,
            sourceTemplateVersion: version.version,
            prescriptionSnapshot: values,
            status: .active,
            autoRecordingPolicy: autoRecording ? .enabled : .disabled
        )
        context.insert(session)

        for prescription in values.sorted(by: { $0.order < $1.order }) {
            let performance = ExercisePerformance(
                sessionID: session.id,
                exerciseID: prescription.exerciseID,
                exerciseName: prescription.exerciseName,
                order: prescription.order,
                prescriptionSnapshot: prescription
            )
            context.insert(performance)
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
        try context.save()
        return session
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
        return TrainingSessionSummary(
            completedSets: sets.count { $0.status == .completed },
            skippedSets: sets.count { $0.status == .skipped },
            completedVolume: sets.compactMap(\.completedVolume).reduce(0, +),
            exerciseCount: performances.count { $0.status == .completed }
        )
    }

    static func archive(
        _ program: TrainingProgram,
        in context: ModelContext
    ) throws {
        program.status = .archived
        try context.save()
    }

    private static func insert(
        _ prescriptions: [TemplateExercisePrescription],
        templateVersionID: UUID,
        in context: ModelContext
    ) {
        for prescription in prescriptions {
            context.insert(TemplateExercise(
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
            ))
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
