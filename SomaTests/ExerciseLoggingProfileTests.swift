@testable import Soma
import SwiftData
import XCTest

final class ExerciseLoggingProfileTests: XCTestCase {
    func testUnsetExerciseUsesDurationWhenOnlySecondsExist() {
        XCTAssertEqual(
            ExerciseLoggingProfile.resolvedTargetKind(
                exercise: nil,
                durationSeconds: 30
            ),
            .duration
        )
        XCTAssertEqual(
            ExerciseLoggingProfile.resolvedTargetKind(
                exercise: nil,
                evidenceTargetKind: .repetitions
            ),
            .repetitions
        )
    }

    func testSetTitleUsesLogicalIndexAndHidesUnspecifiedSide() {
        XCTAssertEqual(
            ExerciseLoggingProfile.setTitle(
                displayIndex: 2,
                logicalSetIndex: 1,
                side: .left
            ),
            "第 1 组 · 左侧"
        )
        XCTAssertEqual(
            ExerciseLoggingProfile.setTitle(
                displayIndex: 3,
                logicalSetIndex: nil,
                side: WorkoutEffortSide.none
            ),
            "第 3 组"
        )
    }

    @MainActor
    func testCatalogDoesNotOverwriteExplicitLoggingProfile() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "侧平板支撑",
            in: context
        )
        exercise.laterality = .none
        exercise.targetKind = .repetitions
        try context.save()

        ExerciseLibraryStore.activateBundledContent(in: context)

        XCTAssertEqual(exercise.laterality, .none)
        XCTAssertEqual(exercise.targetKind, .repetitions)
    }

    @MainActor
    func testCatalogFillsSidePlankLoggingProfileWithoutGuessingNames() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)

        let plank = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "侧平板支撑",
            in: context
        )

        XCTAssertEqual(plank.laterality, .both)
        XCTAssertEqual(plank.targetKind, .duration)
        XCTAssertTrue(plank.hasExplicitLaterality)
        XCTAssertTrue(plank.hasExplicitTargetKind)
    }

    @MainActor
    func testBackfillWritesDurationFromEvidenceAndDoesNotStampDefaultNone() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let exercise = ExerciseDefinition(canonicalName: "虚构悬垂")
        context.insert(exercise)
        let workout = WorkoutEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            exercise: exercise.canonicalName,
            setEntries: [
                WorkoutSetEvidence(targetKind: .duration, durationSeconds: 40)
            ]
        )
        workout.exerciseID = exercise.id
        context.insert(workout)
        try context.save()

        try ExerciseLoggingProfile.backfillIfNeeded(in: context)

        XCTAssertEqual(exercise.targetKind, .duration)
        XCTAssertFalse(exercise.hasExplicitLaterality)
        XCTAssertEqual(exercise.laterality, .none)
    }

    @MainActor
    func testAdoptIfUnsetIgnoresDefaultNoneAndRepetitions() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let exercise = ExerciseDefinition(canonicalName: "虚构深蹲")
        context.insert(exercise)

        ExerciseLoggingProfile.adoptIfUnset(
            exercise,
            laterality: ExerciseLaterality.none,
            targetKind: .repetitions
        )
        XCTAssertFalse(exercise.hasExplicitLaterality)
        XCTAssertFalse(exercise.hasExplicitTargetKind)

        ExerciseLoggingProfile.adoptIfUnset(
            exercise,
            laterality: .both,
            targetKind: .duration
        )
        XCTAssertEqual(exercise.laterality, .both)
        XCTAssertEqual(exercise.targetKind, .duration)
        try context.save()
    }

    @MainActor
    private func makeSpaces() throws -> (DataSpaceController, UserDefaults) {
        let suite = "ExerciseLoggingProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(suite, forKey: "test.suite")
        return (
            DataSpaceController(
                defaults: defaults,
                isStoredInMemoryOnly: true
            ),
            defaults
        )
    }

    private func defaultsSuite(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test.suite") ?? ""
    }
}
