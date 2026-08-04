@testable import Soma
import SwiftData
import XCTest

final class WorkoutSharePosterBuilderTests: XCTestCase {
    func testExerciseSummaryCollapsesUniformBodyweightSets() {
        let sets = (1 ... 5).map { order in
            WorkoutSet(
                performanceID: UUID(),
                order: order,
                plannedReps: 5,
                actualReps: 5,
                actualWeightKG: nil,
                status: .completed
            )
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.exerciseSummary(for: sets),
            "5组 · 自重 × 5"
        )
    }

    func testExerciseSummaryCollapsesUniformLoadedSets() {
        let sets = (1 ... 2).map { order in
            WorkoutSet(
                performanceID: UUID(),
                order: order,
                plannedReps: 5,
                plannedWeightKG: 30,
                actualReps: 5,
                actualWeightKG: 30,
                status: .completed
            )
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.exerciseSummary(for: sets),
            "2组 · 30kg × 5"
        )
    }

    func testExerciseSummaryJoinsVariedSetsAndTruncates() {
        let weights: [Double] = [30, 35, 40, 45, 50]
        let sets = weights.enumerated().map { index, weight in
            WorkoutSet(
                performanceID: UUID(),
                order: index + 1,
                plannedReps: 5,
                actualReps: 5,
                actualWeightKG: weight,
                status: .completed
            )
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.exerciseSummary(for: sets),
            "5组 · 30kg × 5 · 35kg × 5 · 40kg × 5 · 45kg × 5 等"
        )
    }

    @MainActor
    func testProgramDisplayNameOmitsVersionSuffix() throws {
        let session = WorkoutSession(
            programID: UUID(),
            programNameSnapshot: "基础力量训练",
            sourceTemplateVersion: 1,
            status: .completed
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutSession.self,
            configurations: configuration
        )
        let name = WorkoutSharePosterBuilder.programDisplayName(
            for: session,
            in: container.mainContext
        )
        XCTAssertEqual(name, "基础力量训练")
        XCTAssertFalse(name?.contains("v1") == true)
    }

    @MainActor
    func testProgramDisplayNameStripsVersionFromSourceLabel() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutSession.self,
            TrainingProgram.self,
            configurations: configuration
        )
        let context = container.mainContext
        let program = TrainingProgram(name: "推日", status: .active)
        context.insert(program)
        let session = WorkoutSession(
            programID: program.id,
            sourceTemplateVersion: 2,
            status: .completed
        )
        context.insert(session)
        try context.save()

        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: session, in: context),
            "推日 · v2"
        )
        XCTAssertEqual(
            WorkoutSharePosterBuilder.programDisplayName(for: session, in: context),
            "推日"
        )
    }
}
