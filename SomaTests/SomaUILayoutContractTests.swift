@testable import Soma
import XCTest

final class SomaUILayoutContractTests: XCTestCase {
    func testTrainingProgramKeepsEditingVisibleBesideStarting() {
        XCTAssertEqual(
            TrainingProgramDetailAction.allCases,
            [.editPlan, .startTraining]
        )
    }

    func testSettingsFlattensUtilitiesAndKeepsFeedbackLast() {
        XCTAssertEqual(SettingsHomeSection.allCases, [
            .profileAndTraining,
            .service,
            .utilities,
            .display,
            .about,
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
            ProgressHomeSection.visible(hasRecentActivities: true),
            [
                .trainingOverview,
                .monthlyTrend,
                .conclusion,
                .recentActivities,
                .allData,
                .currentGym,
                .personalResources
            ]
        )
        XCTAssertEqual(
            ProgressHomeSection.visible(hasRecentActivities: false),
            [
                .trainingOverview,
                .monthlyTrend,
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

    func testProgressPopoverUsesAvailablePhoneWidthWithBoundedMargins() {
        XCTAssertEqual(ProgressPopoverLayout.width(for: 440), 400)
        XCTAssertEqual(ProgressPopoverLayout.width(for: 375), 351)
        XCTAssertEqual(ProgressPopoverLayout.width(for: 1024), 400)
    }
}
