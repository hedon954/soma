@testable import Soma
import XCTest

final class WorkoutCalorieScopeTests: XCTestCase {
    func testLegacyMETDoesNotProveUserCaloriesAreGross() {
        let old = WorkoutEntry(exercise: "虚构跑步", estimatedCalories: 500, calorieMET: 5)
        XCTAssertEqual(old.calorieScope, .unknown)
        XCTAssertNil(event(old).netEnergy(resting: 1600))
        XCTAssertEqual(old.recordedCalorieOverride, 500)
    }

    func testFormulaAndExplicitActiveCaloriesHaveDifferentNetConversion() {
        let record = WorkoutEntry(exercise: "跑步", durationMinutes: 30)
        WorkoutCalorieCalculator.refreshStoredEstimate(record, weightKG: 70)
        XCTAssertEqual(record.calorieScope, .metGross)
        XCTAssertNotNil(event(record).netEnergy(resting: 1600))
        WorkoutCalorieCalculator.refreshStoredEstimate(record, weightKG: 70, calorieOverride: 500, calorieScope: .active)
        XCTAssertEqual(event(record).netEnergy(resting: 1600), 500)
        // Keep explicit values when only the workout's description or evidence changes.
        WorkoutCalorieCalculator.refreshStoredEstimate(record, weightKG: 71, calorieOverride: record.recordedCalorieOverride)
        XCTAssertEqual(record.calorieScope, .active)
        XCTAssertEqual(record.estimatedCalories, 500)
        WorkoutCalorieCalculator.refreshStoredEstimate(record, weightKG: 71, calorieOverride: 450)
        XCTAssertEqual(record.calorieScope, .unknown)
        XCTAssertNil(event(record).netEnergy(resting: 1600))
    }

    func testArchiveAndTypedArgumentsPreserveExplicitScope() throws {
        let record = WorkoutEntry(exercise: "虚构训练", estimatedCalories: 500, calorieScope: .active)
        let dto = try JSONDecoder().decode(WorkoutEntryDTO.self, from: JSONEncoder().encode(WorkoutEntryDTO(record)))
        XCTAssertEqual(dto.makeModel(mediaPathMapping: [:]).calorieScope, .active)
        let input = try JSONDecoder().decode(AgentWorkoutCreateInput.self, from: Data(#"{"exercise_id":123,"calories":500,"calories_scope":"active"}"#.utf8))
        XCTAssertEqual(input.toolArguments().caloriesScope, .active)
        let mutation = try JSONDecoder().decode(AgentMutationPayload.self, from: Data(#"{"calories_scope":"gross"}"#.utf8))
        XCTAssertEqual(mutation.toolArguments(recordID: 123, recordType: "workout").caloriesScope, .gross)
    }

    private func event(_ entry: WorkoutEntry) -> EnergyTrainingEvent {
        .init(id: "fixture", source: "Soma", scope: entry.calorieScope, kilocalories: entry.estimatedCalories.map(Double.init),
              met: entry.calorieMET, durationHours: 0.5, start: nil, end: nil)
    }
}
