@testable import Soma
import XCTest

final class SomaUILayoutContractTests: XCTestCase {
    func testTrainingProgramKeepsEditingVisibleBesideStarting() {
        XCTAssertEqual(
            TrainingProgramDetailAction.allCases,
            [.editPlan, .startTraining]
        )
    }

    func testSettingsKeepsAppearancePenultimateAndFeedbackLast() {
        XCTAssertEqual(SettingsHomeSection.allCases, [
            .profileAndTraining,
            .service,
            .more,
            .about,
            .display,
            .feedback
        ])
    }

    func testTrainingAlwaysKeepsProgramsAndUsesFrequencyOrder() {
        XCTAssertEqual(
            TrainingHomeSection.visible(
                hasResumableSession: true,
                hasRecentSessions: true,
                hasArchivedPrograms: true
            ),
            [.resume, .programs, .recent, .archived]
        )
        XCTAssertEqual(
            TrainingHomeSection.visible(
                hasResumableSession: false,
                hasRecentSessions: false,
                hasArchivedPrograms: false
            ),
            [.programs]
        )
    }

    func testProgressKeepsSummaryConclusionRecentBeforeTrendsAndData() {
        XCTAssertEqual(
            ProgressHomeSection.visible(
                hasRecentActivities: true,
                hasWeightTrend: true
            ),
            [
                .weekSummary,
                .conclusion,
                .recentActivities,
                .continuityTrend,
                .weightTrend,
                .volumeTrend,
                .allData,
                .currentGym,
                .personalResources
            ]
        )
        XCTAssertEqual(
            ProgressHomeSection.visible(
                hasRecentActivities: false,
                hasWeightTrend: false
            ),
            [
                .weekSummary,
                .conclusion,
                .continuityTrend,
                .volumeTrend,
                .allData,
                .currentGym,
                .personalResources
            ]
        )
    }
}
