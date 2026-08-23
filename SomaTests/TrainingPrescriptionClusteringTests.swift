@testable import Soma
import XCTest

final class TrainingPrescriptionClusteringTests: XCTestCase {
    func testConsecutiveIdenticalDraftsFormOneCluster() {
        let drafts = (1 ... 4).map { order in
            TrainingSetPrescriptionDraft(order: order, reps: "8", weight: "80")
        }

        XCTAssertEqual(
            TrainingPrescriptionDraftClustering.clusters(in: drafts),
            [TrainingPrescriptionCluster(startIndex: 0, count: 4)]
        )
    }

    func testLegacyPerSetRestDoesNotSplitActionParameterClusters() {
        let drafts = [
            TrainingSetPrescriptionDraft(
                order: 1,
                reps: "8",
                weight: "80",
                restAfterSetSeconds: "90"
            ),
            TrainingSetPrescriptionDraft(
                order: 2,
                reps: "8",
                weight: "80"
            )
        ]

        XCTAssertEqual(
            TrainingPrescriptionDraftClustering.clusters(in: drafts),
            [TrainingPrescriptionCluster(startIndex: 0, count: 2)]
        )
    }

    func testWarmupThenWorkingDraftsSplitClusters() {
        let drafts = [
            TrainingSetPrescriptionDraft(order: 1, kind: .warmup, reps: "8", weight: "60"),
            TrainingSetPrescriptionDraft(order: 2, reps: "8", weight: "80"),
            TrainingSetPrescriptionDraft(order: 3, reps: "8", weight: "80"),
            TrainingSetPrescriptionDraft(order: 4, reps: "8", weight: "80")
        ]

        XCTAssertEqual(
            TrainingPrescriptionDraftClustering.clusters(in: drafts),
            [
                TrainingPrescriptionCluster(startIndex: 0, count: 1),
                TrainingPrescriptionCluster(startIndex: 1, count: 3)
            ]
        )
    }

    func testResizeClusterKeepsPrefixIdentitiesAndIndependentCopies() {
        let first = TrainingSetPrescriptionDraft(order: 1, reps: "8")
        let second = TrainingSetPrescriptionDraft(order: 2, reps: "8")
        let resized = TrainingPrescriptionDraftClustering.resize(
            [first, second],
            startIndex: 0,
            count: 2,
            newCount: 4
        )

        XCTAssertEqual(resized.count, 4)
        XCTAssertEqual(resized[0].id, first.id)
        XCTAssertEqual(resized[1].id, second.id)
        XCTAssertEqual(Set(resized.map(\.id)).count, 4)
        XCTAssertEqual(resized.map(\.reps), ["8", "8", "8", "8"])
        XCTAssertEqual(resized.map(\.order), [1, 2, 3, 4])
    }

    func testResizeClusterCannotDeleteTheLastSet() {
        let only = TrainingSetPrescriptionDraft(order: 1, reps: "8")
        let resized = TrainingPrescriptionDraftClustering.resize(
            [only],
            startIndex: 0,
            count: 1,
            newCount: 0
        )
        XCTAssertEqual(resized.map(\.id), [only.id])
    }

    func testMoveClusterSwapsAdjacentWarmupAndWorking() {
        let drafts = [
            TrainingSetPrescriptionDraft(order: 1, kind: .warmup, reps: "8"),
            TrainingSetPrescriptionDraft(order: 2, reps: "10"),
            TrainingSetPrescriptionDraft(order: 3, reps: "10")
        ]
        let moved = TrainingPrescriptionDraftClustering.moveCluster(
            drafts,
            startIndex: 1,
            count: 2,
            direction: -1
        )

        XCTAssertEqual(moved.map(\.kind), [.working, .working, .warmup])
        XCTAssertEqual(moved.map(\.reps), ["10", "10", "8"])
        XCTAssertEqual(moved.map(\.order), [1, 2, 3])
    }
}
