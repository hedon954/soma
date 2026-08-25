import Foundation
import SwiftData

@MainActor
enum DemoTrainingPlanSeeder {
    private static let currentBaselineKey = "demo.trainingPlan.currentBaseline.v1"

    static func seedIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: currentBaselineKey) else { return }
        let programs = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        guard programs.isEmpty else {
            UserDefaults.standard.set(true, forKey: currentBaselineKey)
            return
        }

        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        let preferredNames = ["杠铃深蹲", "引体向上"]
        let exercises = preferredNames.compactMap { preferredName in
            definitions.first { $0.canonicalName == preferredName }
        }
        guard !exercises.isEmpty else { return }

        let prescriptions = exercises.enumerated().map { index, exercise in
            TemplateExercisePrescription(
                exerciseID: exercise.id,
                exerciseName: exercise.canonicalName,
                order: index + 1,
                targetSets: 5,
                targetReps: 5,
                targetWeightKG: exercise.canonicalName == "杠铃深蹲" ? 60 : 0,
                targetRestSeconds: 120,
                firstSetIsWarmup: exercise.canonicalName == "杠铃深蹲"
            )
        }

        _ = try? TrainingPlanStore.createProgram(
            name: "基础力量训练",
            goal: "稳定提升全身基础力量",
            scheduleHint: "按状态完成，动作之间充分休息。",
            prescriptions: prescriptions,
            in: context
        )
        UserDefaults.standard.set(true, forKey: currentBaselineKey)
    }
}
