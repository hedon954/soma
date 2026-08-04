@testable import Soma
import XCTest

final class SomaWidgetSnapshotTests: XCTestCase {
    func testActiveSessionAlwaysOverridesConfiguredQuickCaptureMode() {
        let sessionID = UUID()
        let snapshot = SomaWidgetSnapshot(
            dataSpaceRaw: "personal",
            activeSession: .init(
                id: sessionID,
                completedSetCount: 2,
                totalSetCount: 8,
                planName: "力量 A"
            ),
            weekWorkoutCount: 2
        )
        let preferences = SomaWidgetPreferences(
            displayMode: .quickCapture,
            privacyLevel: .overview
        )

        let content = SomaWidgetContentResolver.resolve(
            snapshot: snapshot,
            preferences: preferences
        )

        XCTAssertEqual(content.kind, .resume)
        XCTAssertEqual(content.title, "继续带练")
        XCTAssertEqual(content.detail, "已完成 2/8 组")
        XCTAssertEqual(
            content.route,
            SomaWidgetContentResolver.workoutRoute(sessionID)
        )
    }

    func testPrivateFixedPlanDoesNotRevealPlanName() {
        let programID = UUID()
        let snapshot = SomaWidgetSnapshot(
            dataSpaceRaw: "personal",
            fixedProgram: .init(id: programID, name: nil)
        )
        let preferences = SomaWidgetPreferences(
            displayMode: .fixedPlan,
            privacyLevel: .privateMode,
            fixedProgramID: programID
        )

        let content = SomaWidgetContentResolver.resolve(
            snapshot: snapshot,
            preferences: preferences
        )

        XCTAssertEqual(content.kind, .fixedPlan)
        XCTAssertEqual(content.title, "准备训练")
        XCTAssertEqual(content.detail, "打开固定训练计划")
        XCTAssertEqual(
            content.route,
            SomaWidgetContentResolver.trainingProgramRoute(programID)
        )
    }

    func testAutomaticFallsBackToRhythmThenFirstTraining() {
        let preferences = SomaWidgetPreferences()
        let rhythm = SomaWidgetContentResolver.resolve(
            snapshot: SomaWidgetSnapshot(
                dataSpaceRaw: "personal",
                weekWorkoutCount: 2
            ),
            preferences: preferences
        )
        let firstTraining = SomaWidgetContentResolver.resolve(
            snapshot: SomaWidgetSnapshot(dataSpaceRaw: "personal"),
            preferences: preferences
        )

        XCTAssertEqual(rhythm.kind, .rhythm)
        XCTAssertEqual(rhythm.detail, "本周已训练 2 次")
        XCTAssertEqual(firstTraining.kind, .firstTraining)
        XCTAssertEqual(firstTraining.title, "开始训练")
    }
}
