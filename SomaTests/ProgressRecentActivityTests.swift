@testable import Soma
import XCTest

final class ProgressRecentActivityTests: XCTestCase {
    func testWorkoutEntryMappingCarriesCompressedEvidenceVolumeAndTime() {
        let date = Date(timeIntervalSince1970: 1_788_280_000)
        let entry = WorkoutEntry(
            date: date,
            exercise: "虚构复盘深蹲",
            exerciseID: UUID(),
            setEntries: (1 ... 5).map { index in
                WorkoutSetEvidence(
                    logicalSetIndex: index,
                    side: nil,
                    targetKind: .repetitions,
                    reps: 5,
                    externalWeightKG: 50,
                    restSeconds: index < 5 ? 60 : nil
                )
            }
        )

        let activity = ProgressRecentActivity.workout(entry)

        XCTAssertEqual(activity.id, entry.id)
        XCTAssertEqual(activity.date, date)
        XCTAssertEqual(activity.title, "虚构复盘深蹲")
        XCTAssertEqual(activity.detail, "5组 × 5次 · 50kg")
        XCTAssertEqual(activity.metric, "1,250 kg")
    }

    func testWorkoutMetricIncludesCaloriesBesideVolume() {
        let entry = WorkoutEntry(
            date: Date(timeIntervalSince1970: 1_788_280_000),
            exercise: "虚构复盘深蹲",
            setEntries: [
                WorkoutSetEvidence(
                    logicalSetIndex: 1,
                    targetKind: .repetitions,
                    reps: 5,
                    externalWeightKG: 50
                )
            ],
            estimatedCalories: 187
        )
        let activity = ProgressRecentActivity.workout(entry)
        XCTAssertEqual(activity.metric, "250 kg\n约 187 kcal")
    }
}
