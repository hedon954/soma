@testable import Soma
import SwiftData
import XCTest

@MainActor
final class EnergyContextToolTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(SomaDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testSchemaAndDecoderOnlyAcceptExplicitUserFacts() throws {
        let data = try JSONEncoder().encode(AgentToolName.recordEnergyContext.chatTool)
        let tool = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let function = try XCTUnwrap(tool["function"] as? [String: Any])
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["energy_context"])
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
        let arguments = try JSONDecoder().decode(AgentToolArguments.self, from: Data(#"{"energy_context":{"work_posture":"sitting","food_complete":false}}"#.utf8))
        XCTAssertEqual(arguments.energyContext?.workPosture, .sitting)
        XCTAssertEqual(arguments.energyContext?.foodComplete, false)
        XCTAssertNil(arguments.energyContext?.trainingComplete)
        XCTAssertThrowsError(try JSONDecoder().decode(AgentToolArguments.self, from: Data(#"{"energy_context":{"food_complete":"true"}}"#.utf8)))
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("factor"))
    }

    func testDateRangeNeverExpandsPastUserMessageOrThirtyOneDays() throws {
        XCTAssertEqual(try EnergyContextStore.dates(from: "2026-10-02", to: "2026-11-01", anchor: day, calendar: calendar).count, 31)
        for (from, to) in [("2026-10-01", "2026-11-01"), ("2026-11-02", "2026-11-02"), ("2026-11-01", "2026-10-31"), ("2026-02-30", "2026-02-30")] {
            XCTAssertThrowsError(try EnergyContextStore.dates(from: from, to: to, anchor: day, calendar: calendar))
        }
    }

    func testBatchConfirmationIsIdempotentAndLifestyleOnlyStartsOnFirstDate() throws {
        let data = try container(), context = data.mainContext
        let dates = [day.addingTimeInterval(-86400), day]
        let patch = EnergyContextPatch(workPosture: .standing, workHours: 8, workDaysPerWeek: 5, foodComplete: true)
        XCTAssertEqual(try EnergyContextStore.save(patch, dates: dates, in: context, now: day, calendar: calendar), 2)
        XCTAssertEqual(try EnergyContextStore.save(patch, dates: dates, in: context, now: day, calendar: calendar), 0)
        let rows = try context.fetch(FetchDescriptor<EnergyContextEntry>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.filter { $0.lifestyleData != nil }.count, 1)
        let later = try XCTUnwrap(EnergyEvidenceStore.contextEntry(for: day, in: context, calendar: calendar))
        let flags = try JSONDecoder().decode(EnergyDayConfirmation.self, from: XCTUnwrap(later.confirmationData))
        XCTAssertEqual(flags.foodComplete, true)
        XCTAssertNotNil(flags.mealEvidenceFingerprint)
        XCTAssertNil(flags.trainingComplete)
    }

    func testMealChangesInvalidateConfirmationUntilExplicitReconfirmation() throws {
        let data = try container(), context = data.mainContext
        let meal = MealEntry(date: day, mealType: .lunch, title: "虚构餐食", calories: 1200)
        context.insert(meal)
        try context.save()
        try EnergyContextStore.save(.init(foodComplete: true), dates: [day], in: context, now: day, calendar: calendar)
        let row = try XCTUnwrap(EnergyEvidenceStore.contextEntry(for: day, in: context, calendar: calendar))
        let flags = try JSONDecoder().decode(EnergyDayConfirmation.self, from: XCTUnwrap(row.confirmationData))
        XCTAssertEqual(flags.mealEvidenceFingerprint, try EnergyFoodEvidence.fingerprint(on: day, in: context, calendar: calendar))
        meal.calories = 1400
        try context.save()
        XCTAssertNotEqual(flags.mealEvidenceFingerprint, try EnergyFoodEvidence.fingerprint(on: day, in: context, calendar: calendar))
        try EnergyContextStore.replace(key: row.key, lifestyle: nil, confirmation: flags, in: context)
        XCTAssertEqual(try JSONDecoder().decode(EnergyDayConfirmation.self, from: XCTUnwrap(row.confirmationData)).mealEvidenceFingerprint, flags.mealEvidenceFingerprint)
        try EnergyContextStore.replace(key: row.key, lifestyle: nil, confirmation: flags, reconfirmFood: true, in: context)
        XCTAssertEqual(try JSONDecoder().decode(EnergyDayConfirmation.self, from: XCTUnwrap(row.confirmationData)).mealEvidenceFingerprint,
                       try EnergyFoodEvidence.fingerprint(on: day, in: context, calendar: calendar))
        try EnergyContextStore.delete(key: row.key, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EnergyContextEntry>()), 0)
    }

    func testNewDatedLifePatchPreservesPreviouslyStatedUnchangedFacts() throws {
        let data = try container(), context = data.mainContext
        try EnergyContextStore.save(.init(workPosture: .standing, workHours: 8, workDaysPerWeek: 5), dates: [day.addingTimeInterval(-86400)],
                                    in: context, now: day, calendar: calendar)
        try EnergyContextStore.save(.init(commutingWalkMinutes: 30), dates: [day], in: context, now: day, calendar: calendar)
        let row = try XCTUnwrap(EnergyEvidenceStore.contextEntry(for: day, in: context, calendar: calendar))
        let facts = try JSONDecoder().decode(EnergyLifestyleFacts.self, from: XCTUnwrap(row.lifestyleData))
        XCTAssertEqual(facts.effectiveFrom, day)
        XCTAssertEqual(facts.workPosture, .standing)
        XCTAssertEqual(facts.workHours, 8)
        XCTAssertEqual(facts.workDaysPerWeek, 5)
        XCTAssertEqual(facts.commutingWalkMinutes, 30)
        XCTAssertNil(facts.houseworkMinutes)
    }

    func testInvalidEditDoesNotMutateExistingFactsAndPrivateEvidenceNeverEntersPrompt() throws {
        let data = try container(), context = data.mainContext
        try EnergyContextStore.save(.init(workPosture: .sitting), dates: [day], in: context, now: day, calendar: calendar)
        let row = try XCTUnwrap(EnergyEvidenceStore.contextEntry(for: day, in: context, calendar: calendar))
        let original = row.lifestyleData
        XCTAssertThrowsError(try EnergyContextStore.replace(key: row.key, lifestyle: .init(effectiveFrom: day, workHours: 25), confirmation: nil, in: context))
        XCTAssertEqual(row.lifestyleData, original)
        try EnergyEvidenceStore.append(EnergyReferenceDay(effectiveFrom: day, factor: 1.98765, reason: "PRIVATE_HEALTH_MARKER"), kind: .reference,
                                       date: day, reason: "PRIVATE_HEALTH_MARKER", in: context)
        let prompt = EnergyContextPrompt.userFacts(in: context, date: day, calendar: calendar)
        XCTAssertTrue(prompt.contains("sitting"))
        XCTAssertFalse(prompt.contains("PRIVATE_HEALTH_MARKER"))
        XCTAssertFalse(prompt.contains("1.98765"))
    }
}
