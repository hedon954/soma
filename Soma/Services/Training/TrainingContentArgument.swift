import Foundation
import SwiftData

struct TrainingContentArgument: Codable, Equatable, Sendable {
    var kind: String
    var programID: Int64? = nil
    var scheduleID: Int64? = nil
    var exercises: [AgentTemplateExerciseInput]? = nil

    enum CodingKeys: String, CodingKey {
        case kind, exercises
        case programID = "program_id"
        case scheduleID = "schedule_id"
    }

    @MainActor
    func resolve(in context: ModelContext) throws -> TrainingContentSource {
        switch kind {
        case "exercise":
            guard programID == nil, scheduleID == nil, let exercises, exercises.count == 1 else {
                throw TrainingContentError.invalid
            }
            let values = try ConversationRecorder.planPrescriptions(
                AgentToolArguments(templateExercises: exercises), in: context
            )
            guard let value = values.first else { throw TrainingContentError.empty }
            return .exercise(value)
        case "course":
            guard exercises == nil, scheduleID == nil, let programID, programID > 0,
                  let program = ConversationRecorder.trainingProgram(businessID: programID, in: context),
                  program.status == .active else { throw TrainingContentError.missing }
            return .course(program.id)
        case "plan":
            guard exercises == nil, programID == nil, let scheduleID, scheduleID > 0 else {
                throw TrainingContentError.invalid
            }
            let descriptor = FetchDescriptor<TrainingSchedule>(predicate: #Predicate { $0.businessID == scheduleID })
            guard let schedule = try context.fetch(descriptor).first else { throw TrainingContentError.missing }
            return .plan(schedule.id)
        default: throw TrainingContentError.invalid
        }
    }
}
