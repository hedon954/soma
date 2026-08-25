import Foundation
import SwiftData

extension ConversationRecorder {
    static func queryPrograms(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> AgentToolResult {
        let filteredPrograms: [TrainingProgram] = if let programID = arguments.programID {
            trainingProgram(businessID: programID, in: context).map { [$0] } ?? []
        } else {
            {
                var descriptor = FetchDescriptor<TrainingProgram>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                if arguments.sort != "name" {
                    let offset = cursorOffset(arguments.cursor)
                    descriptor.fetchLimit = offset == .max
                        ? limit + 1
                        : offset + limit + 1
                }
                return (try? context.fetch(descriptor)) ?? []
            }()
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
            if arguments.projection == "detail" {
                let prescriptions = TrainingPlanStore.prescriptions(
                    for: program,
                    in: context
                )
                let scheduleHint = optionalText(program.scheduleHint)
                    .map(AgentJSONValue.string) ?? .null
                let exercises: [AgentJSONValue] = prescriptions.map { item in
                    .object([
                        "exercise_id": businessIDValue(
                            exerciseBusinessID(item.exerciseID, in: context)
                        ),
                        "name": .string(item.exerciseName),
                        "order": .number(Double(item.order)),
                        "target_sets": .number(Double(item.plannedSets.count)),
                        "target_reps": item.targetReps
                            .map { .number(Double($0)) } ?? .null,
                        "target_weight_kg": item.targetWeightKG
                            .map(AgentJSONValue.number) ?? .null,
                        "target_rest_seconds": item.targetRestSeconds
                            .map { .number(Double($0)) } ?? .null
                    ])
                }
                value["schedule_hint"] = scheduleHint
                value["exercises"] = .array(exercises)
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

    static func querySessions(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> AgentToolResult {
        let filtered: [WorkoutSession] = if let sessionID = arguments.sessionID {
            {
                var descriptor = FetchDescriptor<WorkoutSession>(
                    predicate: #Predicate { $0.businessID == sessionID }
                )
                descriptor.fetchLimit = 1
                return (try? context.fetch(descriptor)) ?? []
            }()
        } else {
            querySessionsPage(arguments, limit: limit, in: context)
        }
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
                in: context
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
        in context: ModelContext
    ) -> String {
        let performances = (
            try? context.fetch(FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.order)]
            ))
        ) ?? []
        let sets = performances.flatMap { performance in
            guard performance.workoutSets.isEmpty else {
                return performance.workoutSets
            }
            let performanceID = performance.id
            return (try? context.fetch(FetchDescriptor<WorkoutSet>(
                predicate: #Predicate { $0.performanceID == performanceID },
                sortBy: [SortDescriptor(\.order)]
            ))) ?? []
        }
        return performances
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

    private static func querySessionsPage(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> [WorkoutSession] {
        let lower = parsedQueryDate(arguments.dateFrom)
        let rawUpper = parsedQueryDate(arguments.dateTo)
        let upper = rawUpper.flatMap { value in
            guard arguments.dateTo?.count == 10 else { return value }
            return Calendar.current.date(byAdding: .day, value: 1, to: value)
        }
        let sort = [SortDescriptor(
            \WorkoutSession.startedAt,
            order: arguments.sort == "oldest" ? .forward : .reverse
        )]
        var descriptor: FetchDescriptor<WorkoutSession> = switch (lower, upper) {
        case let (lower?, upper?):
            FetchDescriptor(
                predicate: #Predicate {
                    $0.startedAt >= lower && $0.startedAt < upper
                },
                sortBy: sort
            )
        case let (lower?, nil):
            FetchDescriptor(
                predicate: #Predicate { $0.startedAt >= lower },
                sortBy: sort
            )
        case let (nil, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.startedAt < upper },
                sortBy: sort
            )
        case (nil, nil):
            FetchDescriptor(sortBy: sort)
        }
        let offset = cursorOffset(arguments.cursor)
        descriptor.fetchLimit = offset == .max
            ? limit + 1
            : offset + limit + 1
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func exerciseBusinessID(
        _ internalID: UUID,
        in context: ModelContext
    ) -> Int64? {
        exerciseDefinition(internalID: internalID, in: context)?.businessID
    }
}
