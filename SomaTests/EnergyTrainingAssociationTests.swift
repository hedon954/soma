@testable import Soma
import SwiftData
import XCTest

@MainActor
final class EnergyTrainingAssociationTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_793_000_000)

    func testWholeSessionSumsActionsAndExplicitLinkPrefersDeviceOnce() throws {
        let first = event("soma:1", kilocalories: 300, scope: .metGross, session: "soma-session:1")
        let second = event("soma:2", kilocalories: 200, scope: .metGross, session: "soma-session:1")
        let grouped = EnergyTrainingGrouping.sessions([first, second])
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.components?.count, 2)
        XCTAssertEqual(grouped.first?.netEnergy(resting: 1600), 400)
        let health = event("health:1", kilocalories: 500, scope: .active)
        let unresolved = try calculate(grouped + [health])
        XCTAssertTrue(unresolved.adoptedTrainingIDs.isEmpty)
        XCTAssertTrue(unresolved.issues.contains { $0.kind == .overlappingTraining })
        let association = EnergyTrainingAssociations(date: day, timeZoneIdentifier: "GMT", links: [.init(localID: "soma-session:1", healthID: health.id)])
        let resolved = try calculate(association.applying(to: grouped + [health]))
        XCTAssertEqual(resolved.adoptedTrainingIDs, [health.id])
        XCTAssertEqual(resolved.excludedTrainingIDs, ["soma-session:1"])
        XCTAssertEqual(try calculate(association.applying(to: grouped)).adoptedTrainingIDs, ["soma-session:1"])
        XCTAssertEqual(try calculate(association.applying(to: grouped)).input.training.first?.netEnergy(resting: 1600), 400)
    }

    func testMissingDeviceEnergyFallsBackToEntireSessionNotOneAction() throws {
        let actions = EnergyTrainingGrouping.sessions([
            event("soma:1", kilocalories: 300, scope: .metGross, session: "soma-session:1"),
            event("soma:2", kilocalories: 200, scope: .metGross, session: "soma-session:1")
        ])
        let health = event("health:1", kilocalories: nil, scope: .active)
        let association = EnergyTrainingAssociations(date: day, timeZoneIdentifier: "GMT", links: [.init(localID: "soma-session:1", healthID: health.id)])
        let result = try calculate(association.applying(to: actions + [health]))
        XCTAssertEqual(result.adoptedTrainingIDs, ["soma-session:1"])
        XCTAssertEqual(result.trainingDelta, 400 - result.displacedActivityPerHour, accuracy: 0.001)
    }

    func testUnknownLocalIntervalCannotBeAddedAgainOnTopOfAnotherSource() throws {
        let local = EnergyTrainingEvent(id: "soma:manual", source: "Soma", scope: .metGross, kilocalories: 300, met: 5,
                                        durationHours: 1, start: nil, end: nil)
        let health = EnergyTrainingEvent(id: "health:coros", source: "COROS", scope: .active, kilocalories: 500, met: nil,
                                         durationHours: 1, start: day, end: day.addingTimeInterval(3600))
        let result = try calculate([local, health])
        XCTAssertEqual(result.adoptedTrainingIDs, [health.id])
        XCTAssertTrue(result.excludedTrainingIDs.contains(local.id))
        XCTAssertTrue(result.issues.contains { $0.kind == .missingTrainingInterval })
        XCTAssertFalse(result.canCalibrate)
    }

    func testLinkUnlinkAreIdempotentPrivateRevisionsAndRejectManyToOne() throws {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        try EnergyTrainingAssociationStore.set(localID: "soma-session:1", healthID: "health:1", on: day, in: context)
        try EnergyTrainingAssociationStore.set(localID: "soma-session:1", healthID: "health:1", on: day, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 1)
        XCTAssertThrowsError(try EnergyTrainingAssociationStore.set(localID: "soma-session:2", healthID: "health:1", on: day, in: context))
        XCTAssertNil(try PersonalDataSnapshot.capture(from: context).withoutHealthActivity().energyEvidence)
        let removed = try EnergyTrainingAssociationStore.set(localID: "soma-session:1", healthID: nil, on: day, in: context)
        XCTAssertTrue(removed.links.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 2)
        XCTAssertTrue(try EnergyTrainingAssociationStore.load(on: day, in: context).links.isEmpty)
    }

    private func event(_ id: String, kilocalories: Double?, scope: WorkoutCalorieScope, session: String? = nil) -> EnergyTrainingEvent {
        .init(id: id, source: "虚构来源", scope: scope, kilocalories: kilocalories, met: 5, durationHours: 1,
              start: day, end: day.addingTimeInterval(3600), sessionIdentity: session)
    }

    private func calculate(_ training: [EnergyTrainingEvent]) throws -> EnergyDayCalculation {
        try EnergyDayCalculator.calculate(.init(date: day, resting: 1600, weightKG: 70,
                                                reference: .init(effectiveFrom: day, factor: 1.4, walkingKilometers: 3, reason: "虚构参考"),
                                                nonTrainingKilometers: 3, walkingCoverageConfirmed: true,
                                                isEndedDay: true, training: training, correction: 0))
    }
}
