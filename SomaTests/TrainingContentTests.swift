@testable import Soma
import SwiftData
import XCTest

final class TrainingContentTests: XCTestCase {
    func testOldSlotsDecodeWithoutNewFields() throws {
        let id = UUID()
        let json = "[{\"kindRaw\":\"course\",\"programID\":\"\(id.uuidString)\"},{\"kindRaw\":\"rest\"}]"
        let slots = try JSONDecoder().decode([TrainingScheduleSlotValue].self, from: Data(json.utf8))
        XCTAssertEqual(slots.map(\.program), [id, nil])
        XCTAssertNil(slots[0].contents)
    }

    @MainActor
    func testMixedContentPreservesRestAndStableIdentityAndDoesNotCreateCourse() throws {
        let context = try makeContext()
        let definition = ExerciseDefinition(canonicalName: "虚构划船")
        context.insert(definition)
        let value = prescription(definition)
        let course = try TrainingPlanStore.createProgram(name: "虚构课程", prescriptions: [value], in: context)
        let nested = TrainingSchedule(name: "嵌套", anchorDate: .now, slots: [.training([.exercise(value)]), .rest()])
        context.insert(nested)
        let root = TrainingSchedule(name: "组合", anchorDate: .now, slots: [
            .training([.exercise(value), .course(course.id), .plan(nested.id)]), .rest()
        ])
        context.insert(root)
        let first = try TrainingContentCompiler.days(scheduleID: root.id, slots: root.slots, in: context)
        let second = try TrainingContentCompiler.days(scheduleID: root.id, slots: root.slots, in: context)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.prescriptions.count), [2, 1, 0, 0])
        XCTAssertEqual(first[0].prescriptions.map(\.order), [1, 2])
        let session = try TrainingPlanStore.startSession(
            prescriptions: first[0].prescriptions, sourceID: first[0].id, name: root.name, in: context
        )
        XCTAssertEqual(session.programID, first[0].id)
        XCTAssertEqual(session.prescriptionSnapshot.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProgram>()), 1)
        try TrainingPlanStore.updateProgram(for: course, name: "修改", scheduleHint: "", prescriptions: [prescription(definition, reps: 9)], in: context)
        XCTAssertEqual(session.prescriptionSnapshot.map { $0.plannedSets[0].targetReps }, [5, 5])
        let refreshed = try TrainingContentCompiler.days(scheduleID: root.id, slots: root.slots, in: context)
        XCTAssertEqual(refreshed[0].prescriptions.map { $0.plannedSets[0].targetReps }, [5, 9])
    }

    @MainActor
    func testCyclesMissingReferencesAndExpandedLimitAreRejected() throws {
        let context = try makeContext()
        let definition = ExerciseDefinition(canonicalName: "虚构动作")
        context.insert(definition)
        let first = TrainingSchedule(name: "A", anchorDate: .now, slots: [])
        let second = TrainingSchedule(name: "B", anchorDate: .now, slots: [.training([.plan(first.id)])])
        context.insert(first)
        context.insert(second)
        first.slots = [.training([.plan(first.id)])]
        XCTAssertThrowsError(try TrainingContentCompiler.days(scheduleID: first.id, slots: first.slots, in: context))
        first.slots = [.training([.plan(second.id)])]
        XCTAssertThrowsError(try TrainingContentCompiler.days(scheduleID: first.id, slots: first.slots, in: context))
        first.slots = [.training([.course(UUID())])]
        XCTAssertThrowsError(try TrainingContentCompiler.days(scheduleID: first.id, slots: first.slots, in: context))
        first.slots = [.training([.exercise(prescription(definition))])] + Array(repeating: .rest(), count: 13)
        second.slots = [.training([.plan(first.id)]), .rest()]
        XCTAssertThrowsError(try TrainingContentCompiler.days(scheduleID: second.id, slots: second.slots, in: context))
    }

    @MainActor
    func testRecentRecommendationKeepsHeterogeneousSetsAndMissingValues() {
        let definition = ExerciseDefinition(canonicalName: "虚构左右划船")
        definition.laterality = .both
        let value = TrainingContentRecommendations.prescription(for: definition, evidence: [
            .init(logicalSetIndex: 1, side: .left, reps: 8, externalWeightKG: 10, restSeconds: 20),
            .init(logicalSetIndex: 1, side: .right, reps: 8, externalWeightKG: 12, restSeconds: 60),
            .init(logicalSetIndex: 2, side: .left, reps: 5),
            .init(logicalSetIndex: 2, side: .right, reps: 5)
        ])
        XCTAssertEqual(value.plannedSets.map(\.targetReps), [8, 5])
        XCTAssertEqual(value.plannedSets.map(\.leftWeightKG), [10, nil])
        XCTAssertEqual(value.plannedSets.map(\.rightWeightKG), [12, nil])
        XCTAssertEqual(value.targetRestSeconds, 60)
        XCTAssertNil(value.targetWeightKG)
    }

    @MainActor
    func testNestedBoundaryRestDaysAreNotOverwrittenBySurroundingExercises() throws {
        let context = try makeContext()
        let exercise = ExerciseDefinition(canonicalName: "虚构边界动作")
        context.insert(exercise)
        let value = prescription(exercise)
        let nested = TrainingSchedule(name: "含休息", anchorDate: .now, slots: [
            .rest(), .training([.exercise(value)]), .rest()
        ])
        context.insert(nested)
        let slots: [TrainingScheduleSlotValue] = [.training([.exercise(value), .plan(nested.id), .exercise(value)])]
        let days = try TrainingContentCompiler.days(scheduleID: UUID(), slots: slots, in: context)
        XCTAssertEqual(days.map(\.prescriptions.count), [1, 0, 1, 0, 1])
    }

    @MainActor
    func testLatestRecommendationUsesLastRecordAndDoesNotWriteFacts() throws {
        let context = try makeContext()
        let exercise = ExerciseDefinition(canonicalName: "虚构历史动作")
        context.insert(exercise)
        XCTAssertNil(try TrainingContentRecommendations.latest(for: exercise, in: context))
        context.insert(WorkoutEntry(date: Date(timeIntervalSince1970: 10), exercise: exercise.canonicalName,
                                    exerciseID: exercise.id, setEntries: [.init(reps: 10, externalWeightKG: 15)]))
        let latest = Date(timeIntervalSince1970: 20)
        context.insert(WorkoutEntry(date: latest, exercise: exercise.canonicalName,
                                    exerciseID: exercise.id, setEntries: [.init(reps: 6), .init(reps: 4, externalWeightKG: 20)]))
        try context.save()
        let result = try XCTUnwrap(TrainingContentRecommendations.latest(for: exercise, in: context))
        XCTAssertEqual(result.sourceDate, latest)
        XCTAssertEqual(result.prescription.plannedSets.map(\.targetReps), [6, 4])
        XCTAssertEqual(result.prescription.plannedSets.map(\.targetWeightKG), [nil, 20])
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEntry>()), 2)
    }

    @MainActor
    func testDirectWorkoutCompletionClosesTheScheduledDay() throws {
        let context = try makeContext()
        let exercise = ExerciseDefinition(canonicalName: "虚构完成动作")
        context.insert(exercise)
        let today = Calendar.current.startOfDay(for: Date())
        let schedule = TrainingSchedule(name: "直接动作", anchorDate: today, slots: [
            .training([.exercise(prescription(exercise))]), .rest()
        ])
        try TrainingScheduleStore.save(schedule, in: context)
        let days = try TrainingContentCompiler.days(scheduleID: schedule.id, slots: schedule.slots, in: context)
        let session = try TrainingPlanStore.startSession(
            prescriptions: days[0].prescriptions, sourceID: days[0].id, name: schedule.name, in: context
        )
        session.startedAt = today
        session.status = .completed
        try context.save()
        let result = try TrainingScheduleStore.sync(schedule, today: today, in: context)
        XCTAssertEqual(result.attention, .settled)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProgram>()), 0)
    }

    @MainActor
    private func prescription(_ definition: ExerciseDefinition, reps: Int = 5) -> TemplateExercisePrescription {
        TemplateExercisePrescription(
            exerciseID: definition.id, exerciseName: definition.canonicalName, order: 1,
            plannedSets: [.init(order: 1, targetReps: reps)]
        )
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SomaDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
