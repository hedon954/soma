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
                .trainingOverview,
                .conclusion,
                .recentActivities,
                .weightTrend,
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
                .trainingOverview,
                .conclusion,
                .allData,
                .currentGym,
                .personalResources
            ]
        )
    }

    func testProgressTrainingOverviewUsesThreeCompactTabs() {
        XCTAssertEqual(
            ProgressTrainingOverviewTab.allCases,
            [.recentWeek, .continuity, .volume]
        )
        XCTAssertEqual(
            ProgressTrainingOverviewTab.allCases.map(\.title),
            ["近 7 天", "连续性", "容量"]
        )
    }
}
