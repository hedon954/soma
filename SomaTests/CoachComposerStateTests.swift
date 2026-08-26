@testable import Soma
import XCTest

/// 输入区状态迁入 `CoachComposerState` 后，草稿合成、建议失配与发送收口
/// 都是纯逻辑；这里固定这些行为，保证隔离重构不改变外显功能。
@MainActor
final class CoachComposerStateTests: XCTestCase {
    /// 单测不真正启动听写（会触发系统授权），只构造服务并注入转写文本。
    private func makeListeningState(draft: String) -> CoachComposerState {
        let state = CoachComposerState()
        state.draft = draft
        state.draftBeforeSpeech = state.trimmedDraft
        state.speechInput = SpeechInputService()
        return state
    }

    func testSyncDraftFromSpeechAppendsTranscriptToBaseline() {
        let state = makeListeningState(draft: "深蹲 5 组")
        state.speechInput?.transcript = "每组 5 次"
        state.syncDraftFromSpeech()
        XCTAssertEqual(state.draft, "深蹲 5 组 每组 5 次")
    }

    func testSyncDraftFromSpeechWithEmptyBaselineUsesTranscriptOnly() {
        let state = makeListeningState(draft: "")
        state.speechInput?.transcript = "记录今天的晚餐"
        state.syncDraftFromSpeech()
        XCTAssertEqual(state.draft, "记录今天的晚餐")
    }

    func testEmptyTranscriptKeepsCurrentDraft() {
        let state = makeListeningState(draft: "硬拉 3 组")
        state.speechInput?.transcript = "   "
        state.syncDraftFromSpeech()
        XCTAssertEqual(state.draft, "硬拉 3 组")
    }

    func testReconcileClearsSuggestionWhenDraftDiverges() {
        let state = CoachComposerState()
        let suggestion = ExerciseInputSuggestion(
            id: UUID(),
            exerciseName: "深蹲",
            recentSummary: "5×5 · 60kg",
            recentDate: .now,
            recordDraft: nil
        )
        state.draft = suggestion.draftText
        state.selectedExerciseSuggestion = suggestion
        state.reconcileSelectedSuggestion()
        XCTAssertNotNil(state.selectedExerciseSuggestion)

        state.draft += "，加一组"
        state.reconcileSelectedSuggestion()
        XCTAssertNil(state.selectedExerciseSuggestion)
    }

    func testClearAfterSubmissionResetsInputsAndDismissesKeyboard() {
        let state = CoachComposerState()
        state.draft = "午餐两个鸡蛋"
        state.attachments = [PendingAttachment(kind: .image, imageData: Data())]
        state.useLocalForNextMessage = true
        state.selectedShortcutID = "shortcut_nutrition"
        let previousDismiss = state.dismissRequest

        state.clearAfterSubmission()

        XCTAssertTrue(state.draft.isEmpty)
        XCTAssertTrue(state.attachments.isEmpty)
        XCTAssertFalse(state.useLocalForNextMessage)
        XCTAssertNil(state.selectedShortcutID)
        XCTAssertNil(state.selectedExerciseSuggestion)
        XCTAssertNotEqual(state.dismissRequest, previousDismiss)
    }

    func testAppendPickedMediaRespectsSelectionCeiling() {
        let state = CoachComposerState()
        state.attachments = (0 ..< (MediaPicker.maximumSelectionCount - 1)).map { _ in
            PendingAttachment(kind: .image, imageData: Data())
        }
        state.appendPickedMedia([
            .image(Data()),
            .image(Data())
        ])
        XCTAssertEqual(
            state.attachments.count,
            MediaPicker.maximumSelectionCount
        )
    }
}
