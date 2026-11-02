@testable import Soma
import SwiftData
import XCTest

@MainActor
final class EnergyRootUpdateTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.insert(UserProfile(biologicalSex: .male, birthDate: Calendar.current.date(byAdding: .year, value: -30, to: .now), height: 170))
        container.mainContext.insert(BodyEntry(date: Calendar.current.startOfDay(for: .now), weight: 70))
        try container.mainContext.save()
        return container
    }

    func testRootComputesWithoutProgressViewAndRejectsPreviousContainerAfterSwitch() async throws {
        let personal = try container(), demo = try container()
        let controller = EnergyRefreshCoordinator()
        controller.bind(context: personal.mainContext, foreground: true)
        controller.bind(context: demo.mainContext, foreground: true)
        let deadline = Date.now.addingTimeInterval(5)
        while try demo.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()) == 0, Date.now < deadline {
            await Task.yield()
        }
        XCTAssertGreaterThan(try demo.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 0)
        XCTAssertEqual(try personal.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 0)
        XCTAssertNil(controller.errorMessage)
        controller.bind(context: nil, foreground: false)
    }

    func testPauseStateSurvivesTimezoneChangeWithoutReinterpretingAnOlderDay() throws {
        let data = try container()
        var east = Calendar(identifier: .gregorian), west = Calendar(identifier: .gregorian)
        east.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        west.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        try EnergyControlStore.setPaused(true, in: data.mainContext, calendar: east)
        XCTAssertTrue(try EnergyControlStore.isPaused(in: data.mainContext))
        try EnergyControlStore.setPaused(false, in: data.mainContext, calendar: west)
        XCTAssertFalse(try EnergyControlStore.isPaused(in: data.mainContext))
        XCTAssertEqual(try data.mainContext.fetchCount(FetchDescriptor<EnergyContextEntry>()), 1)
    }

    func testRestorationCreatesOneForwardRevisionAndPreservesEarlierJudgment() throws {
        let data = try container(), context = data.mainContext
        let today = Calendar.current.startOfDay(for: .now), priorDay = today.addingTimeInterval(-86400)
        func review(on date: Date, correction: Double) -> EnergyCalibrationReview {
            .init(date: date, windowStart: date.addingTimeInterval(-28 * 86400), windowEnd: date,
                  inputFingerprint: "fictional-\(correction)", previousCorrection: 0, nextCorrection: correction,
                  meanIntake: nil, meanModel: nil, slope: nil, minimumCandidate: nil, maximumCandidate: nil,
                  weightDayCount: 12, direction: 1, evidenceEligible: true, reason: "虚构评估")
        }
        let prior = try EnergyEvidenceStore.append(review(on: priorDay, correction: 50), kind: .calibration, date: priorDay,
                                                   reason: "虚构评估", in: context)
        let payload = prior.payload
        try EnergyEvidenceStore.append(review(on: today, correction: 75), kind: .calibration, date: today, reason: "虚构评估", in: context)
        try EnergyControlStore.restore(key: prior.key, in: context, now: today)
        try EnergyControlStore.restore(key: prior.key, in: context, now: today)
        let rows = try context.fetch(FetchDescriptor<EnergyEvidenceEntry>())
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(prior.payload, payload)
        let restored = try XCTUnwrap(rows.first { $0.date == today && $0.revision == 1 })
        let value = try JSONDecoder().decode(EnergyCalibrationReview.self, from: restored.payload)
        XCTAssertEqual(value.nextCorrection, 50)
        XCTAssertEqual(value.previousCorrection, 75)
        XCTAssertEqual(value.restoredFromKey, prior.key)
        XCTAssertFalse(value.evidenceEligible)
    }
}
