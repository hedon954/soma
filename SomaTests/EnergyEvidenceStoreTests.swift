@testable import Soma
import SwiftData
import XCTest

@MainActor
final class EnergyEvidenceStoreTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(SomaDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private var day: Date {
        Date(timeIntervalSince1970: 1_793_000_000)
    }

    func testRepeatedConfirmationDoesNotCreateRowsOrPromoteUnknownFlags() throws {
        let data = try container(), other = try container()
        let confirmation = EnergyDayConfirmation(foodComplete: true)
        try EnergyEvidenceStore.saveConfirmation(confirmation, for: day, in: data.mainContext, now: day)
        try EnergyEvidenceStore.saveConfirmation(confirmation, for: day, in: data.mainContext, now: day)
        XCTAssertEqual(try data.mainContext.fetchCount(FetchDescriptor<EnergyContextEntry>()), 1)
        let row = try XCTUnwrap(EnergyEvidenceStore.contextEntry(for: day, in: data.mainContext))
        let decoded = try JSONDecoder().decode(EnergyDayConfirmation.self, from: XCTUnwrap(row.confirmationData))
        XCTAssertTrue(try XCTUnwrap(decoded.foodComplete))
        XCTAssertNil(decoded.trainingComplete)
        XCTAssertNil(decoded.walkingCoverageComplete)
        XCTAssertEqual(try other.mainContext.fetchCount(FetchDescriptor<EnergyContextEntry>()), 0)
    }

    func testSemanticRevisionPreservesPredecessorEvenWithSameOrReversedClock() throws {
        let data = try container()
        let first = EnergyReferenceDay(effectiveFrom: day, factor: 1.4, walkingKilometers: 3, reason: "虚构参考")
        let row = try EnergyEvidenceStore.append(first, kind: .reference, date: day, reason: first.reason, in: data.mainContext, now: day)
        let repeated = try EnergyEvidenceStore.append(first, kind: .reference, date: day, reason: first.reason, in: data.mainContext, now: day)
        XCTAssertEqual(row.key, repeated.key)
        var changed = first
        changed.factor = 1.5
        let second = try EnergyEvidenceStore.append(changed, kind: .reference, date: day, reason: "用户更正", in: data.mainContext, now: day.addingTimeInterval(-1))
        XCTAssertEqual(second.predecessorKey, row.key)
        XCTAssertEqual(second.revision, 1)
        let restored = try EnergyEvidenceStore.append(first, kind: .reference, date: day, reason: "恢复先前值", in: data.mainContext, now: day)
        XCTAssertEqual(restored.predecessorKey, second.key)
        XCTAssertNotEqual(restored.key, row.key)
        XCTAssertEqual(restored.revision, 2)
        XCTAssertEqual(try data.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 3)
    }

    func testBackupExcludesHealthDerivedEvidenceWhileInternalRollbackPreservesIt() throws {
        let data = try container()
        try EnergyEvidenceStore.saveConfirmation(.init(foodComplete: true), for: day, in: data.mainContext, now: day)
        let reference = EnergyReferenceDay(effectiveFrom: day, factor: 1.4, walkingKilometers: 3, reason: "虚构设备推导")
        try EnergyEvidenceStore.append(reference, kind: .reference, date: day, reason: reference.reason, in: data.mainContext)
        let internalSnapshot = try PersonalDataSnapshot.capture(from: data.mainContext)
        XCTAssertEqual(internalSnapshot.energyEvidence?.count, 1)
        XCTAssertNil(internalSnapshot.withoutHealthActivity().energyEvidence)
        XCTAssertEqual(internalSnapshot.withoutHealthActivity().energyContexts?.count, 1)
        XCTAssertNil(PortableExportPayload(snapshot: internalSnapshot).snapshot.energyEvidence)
        try PersonalDataStore.deleteAllModels(in: data.mainContext)
        try data.mainContext.save()
        XCTAssertEqual(try data.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 0)
        try internalSnapshot.replace(in: data.mainContext, mediaPathMapping: [:])
        XCTAssertEqual(try data.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 1)
        XCTAssertEqual(try data.mainContext.fetchCount(FetchDescriptor<EnergyContextEntry>()), 1)
    }

    func testLegacySnapshotWithoutEnergyTablesRemainsReadable() throws {
        let data = try container()
        let encoded = try JSONEncoder().encode(PersonalDataSnapshot.capture(from: data.mainContext))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "energyContexts")
        object.removeValue(forKey: "energyEvidence")
        let legacy = try JSONDecoder().decode(PersonalDataSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.energyContexts)
        XCTAssertNil(legacy.energyEvidence)
        try legacy.replace(in: data.mainContext, mediaPathMapping: [:])
    }
}
