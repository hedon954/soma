@testable import Soma
import XCTest

final class WorkoutRecordEditorProjectionTests: XCTestCase {
    func testRoundTripPreservesEveryEvidenceFieldAndOrder() {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                side: .left,
                kind: .working,
                targetKind: .repetitions,
                reps: 10,
                externalWeightKG: 16,
                restSeconds: 15,
                recordedVideoPath: "demo-left.mov",
                recordedVideoKind: .partial
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                side: .right,
                kind: .working,
                targetKind: .repetitions,
                reps: 8,
                externalWeightKG: nil,
                restSeconds: 75,
                recordedVideoPath: "demo-right.mov",
                recordedVideoKind: .complete
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 3,
                side: WorkoutEffortSide.none,
                kind: .custom,
                targetKind: .duration,
                durationSeconds: 45,
                externalWeightKG: 0,
                restSeconds: nil
            )
        ]

        XCTAssertEqual(WorkoutRecordEditorProjection(evidence: evidence).evidence, evidence)
    }

    func testLegacyEvidenceWithoutLogicalIndexesStaysAsOrderedGroups() {
        let evidence = [
            WorkoutSetEvidence(reps: 10, externalWeightKG: 20),
            WorkoutSetEvidence(reps: 8, externalWeightKG: 24)
        ]

        let draft = WorkoutRecordDraft(evidence: evidence)

        XCTAssertEqual(draft.groups.count, 2)
        XCTAssertNil(draft.groups[0].logicalSetIndex)
        XCTAssertNil(draft.groups[1].logicalSetIndex)
        XCTAssertEqual(draft.evidence, evidence)
    }

    func testLeftAndRightEffortsShareOneAlternatingLogicalGroup() {
        let draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .left,
                targetKind: .repetitions,
                reps: 10,
                restSeconds: 15
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .right,
                targetKind: .repetitions,
                reps: 10,
                restSeconds: 75
            )
        ])

        XCTAssertEqual(draft.groups.count, 1)
        XCTAssertEqual(draft.groups[0].sideMode, .alternating)
        XCTAssertEqual(draft.groups[0].restPresentation.betweenSidesSeconds, 15)
        XCTAssertEqual(draft.groups[0].restPresentation.afterGroupSeconds, 75)
        XCTAssertFalse(draft.groups[0].restPresentation.isAmbiguous)
    }

    func testSideModesCoverSimultaneousAndSingleSides() {
        let simultaneous = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: WorkoutEffortSide.none,
                reps: 10
            )
        ])
        let left = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, side: .left, reps: 10)
        ])
        let right = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, side: .right, reps: 10)
        ])

        XCTAssertEqual(simultaneous.groups[0].sideMode, .simultaneous)
        XCTAssertEqual(left.groups[0].sideMode, .leftOnly)
        XCTAssertEqual(right.groups[0].sideMode, .rightOnly)
    }

    func testOnlyConsecutiveDisplayIdenticalGroupsCollapse() {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                targetKind: .repetitions,
                reps: 10,
                externalWeightKG: 20
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                targetKind: .repetitions,
                reps: 10,
                externalWeightKG: 20
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 3,
                targetKind: .repetitions,
                reps: 8,
                externalWeightKG: 24
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 4,
                targetKind: .repetitions,
                reps: 10,
                externalWeightKG: 20
            )
        ]

        let runs = WorkoutRecordDraft(evidence: evidence).displayRuns

        XCTAssertEqual(runs.map(\.count), [2, 1, 1])
    }

    func testCompressionIgnoresRestWithoutChangingStoredEvidence() {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 10,
                externalWeightKG: 20,
                restSeconds: 60
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                reps: 10,
                externalWeightKG: 20,
                restSeconds: 75
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 3,
                reps: 10,
                externalWeightKG: 20,
                restSeconds: nil
            )
        ]

        let draft = WorkoutRecordDraft(evidence: evidence)

        XCTAssertEqual(draft.displayRuns.map(\.count), [3])
        XCTAssertEqual(draft.evidence, evidence)
    }

    func testFinalLogicalGroupIsExcludedFromAfterGroupRestTargets() throws {
        let draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, reps: 10, restSeconds: 60),
            WorkoutSetEvidence(logicalSetIndex: 2, reps: 10, restSeconds: nil)
        ])
        let run = try XCTUnwrap(draft.displayRuns.first)

        XCTAssertEqual(
            run.restTargetGroupIDs(
                effortIndex: 0,
                effortCount: 1,
                finalGroupID: draft.finalGroupID
            ),
            [draft.groups[0].id]
        )
    }

    func testFinalAlternatingGroupKeepsBetweenSidesRestTarget() throws {
        let draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, side: .left, reps: 10, restSeconds: 15),
            WorkoutSetEvidence(logicalSetIndex: 1, side: .right, reps: 10, restSeconds: nil)
        ])
        let run = try XCTUnwrap(draft.displayRuns.first)

        XCTAssertEqual(
            run.restTargetGroupIDs(
                effortIndex: 0,
                effortCount: 2,
                finalGroupID: draft.finalGroupID
            ),
            [draft.groups[0].id]
        )
        XCTAssertTrue(
            run.restTargetGroupIDs(
                effortIndex: 1,
                effortCount: 2,
                finalGroupID: draft.finalGroupID
            ).isEmpty
        )
    }

    func testCompressionDoesNotDiscardDifferentRecordingMetadata() {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 10,
                recordedVideoPath: "demo-1.mov",
                recordedVideoKind: .complete
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                reps: 10,
                recordedVideoPath: "demo-2.mov",
                recordedVideoKind: .partial
            )
        ]

        let projection = WorkoutRecordEditorProjection(evidence: evidence)

        XCTAssertEqual(projection.displayRuns.map(\.count), [2])
        XCTAssertEqual(projection.evidence, evidence)
    }

    func testCopyCreatesNewLogicalGroupWithoutCopyingRecordingEvidence() {
        var draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(
                logicalSetIndex: 4,
                side: .left,
                reps: 12,
                recordedVideoPath: "demo.mov",
                recordedVideoKind: .complete
            )
        ])

        draft.appendGroup(copying: draft.groups[0].id)

        XCTAssertEqual(draft.groups.map(\.logicalSetIndex), [4, 5])
        XCTAssertEqual(draft.groups[1].efforts[0].reps, 12)
        XCTAssertNil(draft.groups[1].efforts[0].recordedVideoPath)
        XCTAssertNil(draft.groups[1].efforts[0].recordedVideoKind)
    }

    func testAddInheritsStructureWithoutInventingValues() {
        var draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .left,
                targetKind: .duration,
                durationSeconds: 30,
                externalWeightKG: 12,
                restSeconds: 15
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .right,
                targetKind: .duration,
                durationSeconds: 30,
                externalWeightKG: 14,
                restSeconds: 60
            )
        ])

        draft.appendGroup()

        let added = draft.groups[1]
        XCTAssertEqual(added.sideMode, .alternating)
        XCTAssertEqual(added.efforts.map(\.targetKind), [.duration, .duration])
        XCTAssertTrue(added.efforts.allSatisfy { $0.durationSeconds == nil })
        XCTAssertTrue(added.efforts.allSatisfy { $0.externalWeightKG == nil })
        XCTAssertTrue(added.efforts.allSatisfy { $0.restSeconds == nil })
    }

    func testDurationClearsRepetitionsOnlyWhenBuildingEditedEvidence() {
        let effort = WorkoutEffortDraft(
            sourceOrder: 0,
            targetKind: .duration,
            reps: 99,
            durationSeconds: 60
        )

        let evidence = effort.evidence(logicalSetIndex: 1)

        XCTAssertNil(evidence.reps)
        XCTAssertEqual(evidence.durationSeconds, 60)
    }

    func testLegacyMissingTargetKindRemainsMissingAfterRoundTrip() {
        let evidence = [WorkoutSetEvidence(reps: 8, externalWeightKG: 40)]

        let roundTrip = WorkoutRecordDraft(evidence: evidence).evidence

        XCTAssertEqual(roundTrip, evidence)
        XCTAssertNil(roundTrip[0].targetKind)
    }

    func testRemovingOneGroupPreservesRemainingOrderAndEvidence() {
        var draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, reps: 12, externalWeightKG: 20),
            WorkoutSetEvidence(logicalSetIndex: 2, reps: 10, externalWeightKG: 24),
            WorkoutSetEvidence(logicalSetIndex: 3, reps: 8, externalWeightKG: 28)
        ])

        draft.removeGroup(id: draft.groups[1].id)

        XCTAssertEqual(draft.groups.map(\.logicalSetIndex), [1, 3])
        XCTAssertEqual(draft.evidence.map(\.reps), [12, 8])
        XCTAssertEqual(draft.evidence.map(\.externalWeightKG), [20, 28])
    }

    func testEditingCompressedRunDoesNotPolluteAdjacentDifferentGroup() {
        var draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, reps: 10, externalWeightKG: 20),
            WorkoutSetEvidence(logicalSetIndex: 2, reps: 10, externalWeightKG: 20),
            WorkoutSetEvidence(logicalSetIndex: 3, reps: 8, externalWeightKG: 30)
        ])
        let compressedIDs = Set(draft.displayRuns[0].groups.map(\.id))

        draft.updateEffortValue(
            in: compressedIDs,
            effortIndex: 0,
            keyPath: \.externalWeightKG,
            value: 22
        )

        XCTAssertEqual(draft.evidence.map(\.externalWeightKG), [22, 22, 30])
        XCTAssertEqual(draft.evidence.map(\.reps), [10, 10, 8])
    }

    func testValidationRejectsOutOfRangeValuesWithoutRejectingMissingFacts() {
        var draft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(logicalSetIndex: 1, reps: nil, externalWeightKG: nil)
        ])
        XCTAssertTrue(draft.isValid)

        let groupID = draft.groups[0].id
        draft.updateEffortValue(
            in: [groupID],
            effortIndex: 0,
            keyPath: \.reps,
            value: 0
        )
        XCTAssertFalse(draft.isValid)

        draft.updateEffortValue(
            in: [groupID],
            effortIndex: 0,
            keyPath: \.reps,
            value: 1
        )
        XCTAssertTrue(draft.isValid)
    }
}
