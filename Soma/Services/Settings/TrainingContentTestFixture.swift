import Foundation
import SwiftData

@MainActor
enum TrainingContentTestFixture {
    static func seedIfRequested(in context: ModelContext) {
        guard AppTestRuntime.isRunning,
              ProcessInfo.processInfo.environment["SOMA_UI_TRAINING_CONTENT_FIXTURE"] == "1"
        else { return }
        do {
            let name = "虚构深蹲"
            let descriptor = FetchDescriptor<ExerciseDefinition>(predicate: #Predicate { $0.canonicalName == name })
            guard try context.fetch(descriptor).isEmpty else { return }
            let exercise = ExerciseDefinition(canonicalName: name)
            context.insert(exercise)
            context.insert(WorkoutEntry(
                date: .now, exercise: name, exerciseID: exercise.id,
                setEntries: [.init(reps: 8, externalWeightKG: 20), .init(reps: 5, externalWeightKG: 25)]
            ))
            if ProcessInfo.processInfo.environment["SOMA_UI_TRAINING_PICKER_TABS_FIXTURE"] == "1" {
                let value = TemplateExercisePrescription(
                    exerciseID: exercise.id, exerciseName: name, order: 1,
                    plannedSets: [.init(order: 1, targetReps: 8)]
                )
                _ = try TrainingPlanStore.createProgram(name: "虚构课程", prescriptions: [value], in: context)
                context.insert(TrainingSchedule(
                    name: "虚构引用计划", status: .archived, anchorDate: .now,
                    slots: [.training([.exercise(value)]), .rest()]
                ))
                for index in 0 ..< 80 {
                    context.insert(ExerciseDefinition(canonicalName: "分类动作 \(index)"))
                }
            }
            try context.save()
        } catch { assertionFailure("Training content fixture failed") }
    }
}
