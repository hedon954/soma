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
}
