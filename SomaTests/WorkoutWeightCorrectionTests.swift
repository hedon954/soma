@testable import Soma
import SwiftData
import XCTest

final class WorkoutWeightCorrectionTests: XCTestCase {
    @MainActor
    func testGuidedSideUpdatesActualSourceAndKeepsPrescription() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Soma.WeightGuided.\(UUID())"))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = spaces.personalContainer.mainContext
        let performanceID = UUID()
        let set = WorkoutSet(
            performanceID: performanceID, order: 1, plannedWeightKG: 40, actualWeightKG: 40, status: .completed
        )
        let left = WorkoutEffort(workoutSetID: set.id, order: 1, side: .left, plannedWeightKG: 40, actualReps: 10, actualWeightKG: 40, status: .completed)
        let right = WorkoutEffort(workoutSetID: set.id, order: 2, side: .right, plannedWeightKG: 40, actualReps: 10, actualWeightKG: 40, status: .completed)
        set.efforts = [left, right]
        let entry = WorkoutEntry(exercise: "交替哑铃卧推", setEntries: [
            .init(logicalSetIndex: 1, side: .left, reps: 10, externalWeightKG: 40),
            .init(logicalSetIndex: 1, side: .right, reps: 10, externalWeightKG: 40)
        ])
        entry.sourcePerformanceID = performanceID
        context.insert(set)
        context.insert(entry)
        try context.save()

        let plan = try WorkoutWeightCorrection.preview(in: context)
        XCTAssertEqual(plan.changes.count, 2)
        left.actualReps = 9
        try context.save()
        XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .conflict)
        XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: false, in: context))
        XCTAssertEqual(left.actualWeightKG, 40)
        XCTAssertEqual(right.actualWeightKG, 40)
        left.actualReps = 10
        try context.save()
        try WorkoutWeightCorrection.commit(plan, undo: false, in: context)
        XCTAssertEqual(entry.estimatedVolume, 400)
        XCTAssertEqual(set.actualWeightKG, 20)
        XCTAssertEqual(left.actualWeightKG, 20)
        XCTAssertEqual(right.actualWeightKG, 20)
        XCTAssertEqual(left.plannedWeightKG, 40)
        XCTAssertEqual(set.plannedWeightKG, 40)
        set.performanceID = UUID()
        try context.save()
        XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .conflict)
        XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: true, in: context))
        XCTAssertEqual(left.actualWeightKG, 20)
        XCTAssertEqual(right.actualWeightKG, 20)
        set.performanceID = performanceID
        try context.save()
        try WorkoutWeightCorrection.commit(plan, undo: true, in: context)
        XCTAssertEqual(right.actualWeightKG, 40)
        XCTAssertEqual(entry.estimatedVolume, 800)
    }

    @MainActor
    func testMixedEffortsAndLegacyWeightsApplyOnceAndRestore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Soma.WeightCorrection.\(UUID())"))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = spaces.personalContainer.mainContext
        let paired = WorkoutEntry(exercise: "上斜哑铃交替弯举", setEntries: [
            .init(logicalSetIndex: 1, side: .left, reps: 6, externalWeightKG: 40, restSeconds: 50),
            .init(logicalSetIndex: 1, side: .right, reps: 8, externalWeightKG: 19.99, restSeconds: 30),
            .init(logicalSetIndex: 2, side: .left, reps: 9, externalWeightKG: 20)
        ])
        let legacy = WorkoutEntry(exercise: "哑铃垂式弯举", sets: 3, reps: 5, weight: 25)
        let unrelated = WorkoutEntry(exercise: "哑铃划船", sets: 3, reps: 5, weight: 28)
        [paired, legacy, unrelated].forEach(context.insert)
        try context.save()

        let plan = try WorkoutWeightCorrection.preview(in: context)
        XCTAssertEqual(plan.changes.count, 3)
        XCTAssertEqual(plan.conflicts, 0)
        XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .before)
        try WorkoutWeightCorrection.commit(plan, undo: false, in: context)
        try WorkoutWeightCorrection.commit(plan, undo: false, in: context)
        XCTAssertEqual(paired.setEntries.compactMap(\.externalWeightKG), [20, 19.99, 10])
        XCTAssertEqual(paired.setEntries.first?.restSeconds, 50)
        XCTAssertEqual(legacy.weight, 12.5)
        XCTAssertEqual(unrelated.weight, 28)
        XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .after)
        try WorkoutWeightCorrection.commit(plan, undo: true, in: context)
        XCTAssertEqual(paired.setEntries.compactMap(\.externalWeightKG), [40, 19.99, 20])
        XCTAssertEqual(legacy.weight, 25)
    }

    @MainActor
    func testInclineDumbbellCurlCoversCatalogAliasWithoutChangingLowerWeights() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Soma.WeightIncline.\(UUID())"))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = spaces.personalContainer.mainContext
        let canonical = WorkoutEntry(exercise: "上斜哑铃弯举", setEntries: [
            .init(logicalSetIndex: 1, side: .left, reps: 10, externalWeightKG: 20),
            .init(logicalSetIndex: 1, side: .right, reps: 10, externalWeightKG: 19.99)
        ])
        let alias = WorkoutEntry(exercise: "上斜凳弯举", sets: 3, reps: 8, weight: 22)
        let other = WorkoutEntry(exercise: "斜托弯举", sets: 3, reps: 8, weight: 22)
        [canonical, alias, other].forEach(context.insert)
        try context.save()

        let plan = try WorkoutWeightCorrection.preview(in: context)
        XCTAssertEqual(Set(plan.changes.map(\.workoutID)), [canonical.id, alias.id])
        try WorkoutWeightCorrection.commit(plan, undo: false, in: context)
        XCTAssertEqual(canonical.setEntries.compactMap(\.externalWeightKG), [10, 19.99])
        XCTAssertEqual(alias.weight, 11)
        XCTAssertEqual(other.weight, 22)
    }

    @MainActor
    func testUnexpectedEditPreventsWritingTheRestOfThePlan() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Soma.WeightConflict.\(UUID())"))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = spaces.personalContainer.mainContext
        let changed = WorkoutEntry(exercise: "上斜哑铃卧推", sets: 2, reps: 8, weight: 30)
        let untouched = WorkoutEntry(exercise: "交替哑铃卧推", sets: 2, reps: 6, weight: 40)
        context.insert(changed)
        context.insert(untouched)
        try context.save()
        let plan = try WorkoutWeightCorrection.preview(in: context)
        changed.reps = 9
        try context.save()
        XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .conflict)
        XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: false, in: context))
        XCTAssertEqual(untouched.weight, 40)

        changed.reps = 8
        changed.weight = 32
        try context.save()
        XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: false, in: context))
        XCTAssertEqual(untouched.weight, 40)
    }

    @MainActor
    func testDiskJournalSurvivesReopeningAndGuardsApplyAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SomaWeightCorrection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appending(path: "workout-weight-correction-082.json")
        let missingJournal = directory.appending(path: "missing-journal.json")
        let plan: WorkoutWeightCorrectionPlan

        do {
            let container = try openPersonalStore(at: directory)
            let context = container.mainContext
            let entry = WorkoutEntry(exercise: "上斜交替哑铃卧推", setEntries: [
                .init(logicalSetIndex: 1, side: .left, reps: 10, externalWeightKG: 40),
                .init(logicalSetIndex: 1, side: .right, reps: 10, externalWeightKG: 20),
                .init(logicalSetIndex: 2, side: .left, reps: 10, externalWeightKG: 19.99)
            ])
            context.insert(entry)
            try context.save()
            plan = try WorkoutWeightCorrection.preview(in: context)
            XCTAssertEqual(plan.changes.map(\.previous), [40, 20])
            let original = entry.setEntries
            var revised = original
            revised[0].reps = 9
            entry.setEntries = revised
            try context.save()

            XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: false, in: context, journalURL: journal))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
            XCTAssertEqual(entry.setEntries.compactMap(\.externalWeightKG), [40, 20, 19.99])

            entry.setEntries = original
            try context.save()
            try WorkoutWeightCorrection.commit(plan, undo: false, in: context, journalURL: journal)
            XCTAssertEqual(try JSONDecoder().decode(WorkoutWeightCorrectionPlan.self, from: Data(contentsOf: journal)), plan)
            XCTAssertEqual(entry.setEntries.compactMap(\.externalWeightKG), [20, 10, 19.99])
        }

        do {
            let container = try openPersonalStore(at: directory)
            let context = container.mainContext
            let entry = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)
            XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .after)
            XCTAssertEqual(try XCTUnwrap(entry.estimatedVolume), 499.9, accuracy: 0.001)
            try WorkoutWeightCorrection.commit(plan, undo: false, in: context, journalURL: journal)
            XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: false, in: context, journalURL: missingJournal))
            XCTAssertThrowsError(try WorkoutWeightCorrection.commit(plan, undo: true, in: context, journalURL: missingJournal))
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingJournal.path))
            XCTAssertEqual(entry.setEntries.compactMap(\.externalWeightKG), [20, 10, 19.99])

            let added = WorkoutEntry(exercise: "上斜哑铃弯举", sets: 2, reps: 8, weight: 24)
            context.insert(added)
            try context.save()
            let whileApplied = try WorkoutWeightCorrection.preview(in: context)
            XCTAssertThrowsError(try WorkoutWeightCorrection.commit(whileApplied, undo: false, in: context, journalURL: journal))
            XCTAssertEqual(try WorkoutWeightCorrection.loadPlan(in: context, journalURL: journal).plan, plan)
            XCTAssertEqual(entry.setEntries.compactMap(\.externalWeightKG), [20, 10, 19.99])
            try WorkoutWeightCorrection.commit(plan, undo: true, in: context, journalURL: journal)
        }

        let container = try openPersonalStore(at: directory)
        let context = container.mainContext
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        let entry = try XCTUnwrap(workouts.first { $0.exercise == "上斜交替哑铃卧推" })
        let added = try XCTUnwrap(workouts.first { $0.exercise == "上斜哑铃弯举" })
        XCTAssertEqual(try WorkoutWeightCorrection.state(of: plan, in: context), .before)
        XCTAssertEqual(entry.setEntries.compactMap(\.externalWeightKG), [40, 20, 19.99])
        XCTAssertEqual(try XCTUnwrap(entry.estimatedVolume), 799.9, accuracy: 0.001)

        let refreshed = try WorkoutWeightCorrection.loadPlan(in: context, journalURL: journal)
        XCTAssertEqual(refreshed.state, .before)
        try WorkoutWeightCorrection.commit(refreshed.plan, undo: false, in: context, journalURL: journal)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutWeightCorrectionPlan.self, from: Data(contentsOf: journal)), refreshed.plan)
        XCTAssertEqual(entry.setEntries.compactMap(\.externalWeightKG), [20, 10, 19.99])
        XCTAssertEqual(added.weight, 12)
    }

    private func openPersonalStore(at directory: URL) throws -> ModelContainer {
        try SomaStoreOpening.makeContainer(
            configurationName: "PersonalData",
            schema: Schema(SomaDataSchema.models),
            isStoredInMemoryOnly: false,
            url: directory.appending(path: "PersonalData.store"),
            stepName: "重量校正磁盘夹具"
        )
    }
}
