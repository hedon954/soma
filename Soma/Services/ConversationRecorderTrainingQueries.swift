import Foundation
import SwiftData

extension ConversationRecorder {
    static func queryPrograms(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> AgentToolResult {
        let programs = (
            try? context.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        let versions = (
            try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
        ) ?? []
        let sortedPrograms: [TrainingProgram] = programs.sorted {
            $0.updatedAt > $1.updatedAt
        }
        let filteredPrograms: [TrainingProgram] = if let programID = arguments.programID {
            sortedPrograms.filter {
                $0.businessID == programID
            }
        } else {
            sortedPrograms
        }

        var values = [[String: AgentJSONValue]]()
        values.reserveCapacity(filteredPrograms.count)
        for program in filteredPrograms {
            let goal = optionalText(program.goal)
                .map(AgentJSONValue.string) ?? .null
            var value: [String: AgentJSONValue] = [
                "program_id": businessIDValue(program.businessID),
                "name": .string(program.name),
                "goal": goal,
                "status": .string(program.status.rawValue)
            ]
            if arguments.projection == "detail",
               let version = versions.first(where: {
                   $0.id == program.currentTemplateVersionID
               })
            {
                let prescriptions = TrainingPlanStore.prescriptions(
                    for: version,
                    in: context
                )
                let scheduleHint = optionalText(version.scheduleHint)
                    .map(AgentJSONValue.string) ?? .null
                let exercises: [AgentJSONValue] = prescriptions.map { item in
                    .object([
                        "exercise_id": businessIDValue(
                            exerciseBusinessID(item.exerciseID, in: context)
                        ),
                        "name": .string(item.exerciseName),
                        "order": .number(Double(item.order)),
                        "target_sets": item.targetSets
                            .map { .number(Double($0)) } ?? .null,
                        "target_reps": item.targetReps
                            .map { .number(Double($0)) } ?? .null,
                        "target_weight_kg": item.targetWeightKG
                            .map(AgentJSONValue.number) ?? .null,
                        "target_rest_seconds": item.targetRestSeconds
                            .map { .number(Double($0)) } ?? .null
                    ])
                }
                value["current_template"] = .object([
                    "record_id": businessIDValue(version.businessID),
                    "name": .string(version.name),
                    "version": .number(Double(version.version)),
                    "schedule_hint": scheduleHint,
                    "exercises": .array(exercises)
                ])
            }
            values.append(value)
        }
        return pagedResult(
            values,
            noun: "训练计划",
            arguments: arguments,
            limit: limit
        )
    }

    static func queryTemplates(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> AgentToolResult {
        let versions = (
            try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
        ) ?? []
        let programs = (
            try? context.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        let filtered: [WorkoutTemplateVersion] = if let businessID = arguments.programID,
                                                    let program = programs.first(where: {
                                                        $0.businessID == businessID
                                                    })
        {
            versions.filter { $0.programID == program.id }
        } else {
            versions
        }
        let values = filtered
            .filter {
                arguments.recordID == nil
                    || $0.businessID == arguments.recordID
            }
            .sorted { lhs, rhs in
                lhs.createdAt == rhs.createdAt
                    ? lhs.version > rhs.version
                    : lhs.createdAt > rhs.createdAt
            }
            .map { version in
                var value = [
                    "record_id": businessIDValue(version.businessID),
                    "program_id": businessIDValue(
                        programs.first(where: { $0.id == version.programID })?.businessID
                    ),
                    "name": .string(version.name),
                    "version": .number(Double(version.version))
                ] as [String: AgentJSONValue]
                if arguments.projection == "detail" {
                    let scheduleHint = optionalText(version.scheduleHint)
                        .map(AgentJSONValue.string) ?? .null
                    let prescriptions = TrainingPlanStore.prescriptions(
                        for: version,
                        in: context
                    )
                    let exercises: [AgentJSONValue] = prescriptions.map { item in
                        .object([
                            "exercise_id": businessIDValue(
                                exerciseBusinessID(item.exerciseID, in: context)
                            ),
                            "name": .string(item.exerciseName),
                            "order": .number(Double(item.order))
                        ])
                    }
                    value["schedule_hint"] = scheduleHint
                    value["exercises"] = .array(exercises)
                }
                return value
            }
        return pagedResult(
            values,
            noun: "训练模板",
            arguments: arguments,
            limit: limit
        )
    }

    static func querySessions(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> AgentToolResult {
        let sessions = (
            try? context.fetch(FetchDescriptor<WorkoutSession>())
        ) ?? []
        let filtered: [WorkoutSession] = if let sessionID = arguments.sessionID {
            sessions.filter { $0.businessID == sessionID }
        } else {
            sessions
        }
        let performances = (
            try? context.fetch(FetchDescriptor<ExercisePerformance>())
        ) ?? []
        let sets = (
            try? context.fetch(FetchDescriptor<WorkoutSet>())
        ) ?? []
        let values = filteredByDate(
            filtered,
            arguments: arguments,
            date: \.startedAt
        )
        .sorted { $0.startedAt > $1.startedAt }
        .map { session in
            let summary = TrainingPlanStore.summary(
                for: session.id,
                in: context
            )
            let details = sessionDetails(
                sessionID: session.id,
                performances: performances,
                sets: sets
            )
            return [
                "session_id": businessIDValue(session.businessID),
                "date": .string(session.startedAt.ISO8601Format()),
                "status": .string(session.status.rawValue),
                "summary": .string(summary.text),
                "details": .string(details)
            ] as [String: AgentJSONValue]
        }
        return pagedResult(
            values,
            noun: "计划训练",
            arguments: arguments,
            limit: limit
        )
    }

    private static func sessionDetails(
        sessionID: UUID,
        performances: [ExercisePerformance],
        sets: [WorkoutSet]
    ) -> String {
        performances
            .filter { $0.sessionID == sessionID }
            .sorted { $0.order < $1.order }
            .map { performance in
                let completed = sets.filter {
                    $0.performanceID == performance.id
                        && $0.status == .completed
                }
                let setText = completed.map { set in
                    [
                        set.actualWeightKG.map {
                            "\($0.formatted())kg"
                        },
                        set.actualReps.map { "\($0)次" }
                    ]
                    .compactMap { $0 }
                    .joined(separator: "×")
                }
                .filter { !$0.isEmpty }
                .joined(separator: "、")
                return "\(performance.exerciseName)：\(completed.count)组"
                    + (setText.isEmpty ? "" : "（\(setText)）")
            }
            .joined(separator: "；")
    }

    private static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func exerciseBusinessID(
        _ internalID: UUID,
        in context: ModelContext
    ) -> Int64? {
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        return definitions.first(where: { $0.id == internalID })?.businessID
    }

    private static func businessIDValue(_ id: Int64?) -> AgentJSONValue {
        id.map { .number(Double($0)) } ?? .null
    }
}
