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

    func testSpeechAccumulatorNeverLetsShorterPartialEraseCommittedPrefix() {
        var accumulator = SpeechTranscriptAccumulator()
        XCTAssertEqual(
            accumulator.receive(
                "今天练深蹲",
                isFinal: false,
                speechSegmentStart: 0,
                speechSegmentEnd: 0.8
            ),
            "今天练深蹲"
        )
        XCTAssertEqual(
            accumulator.receive(
                "今天练",
                isFinal: false,
                speechSegmentStart: 0,
                speechSegmentEnd: 0.8
            ),
            "今天练深蹲"
        )
        XCTAssertEqual(accumulator.receive("今天练深蹲", isFinal: true), "今天练深蹲，")
        XCTAssertEqual(accumulator.receive("五组", isFinal: false), "今天练深蹲，五组")
        XCTAssertEqual(accumulator.receive("五组五次", isFinal: true), "今天练深蹲，五组五次，")
    }

    func testSameAudioTextRevisionDoesNotMoveSilenceBoundary() {
        var accumulator = SpeechTranscriptAccumulator()
        let start = Date(timeIntervalSince1970: 3000)

        XCTAssertEqual(
            accumulator.receive(
                "第一段训练",
                isFinal: false,
                at: start,
                speechSegmentStart: 0,
                speechSegmentEnd: 0.6
            ),
            "第一段训练"
        )
        let activityRevision = accumulator.speechActivityRevision

        // Speech.framework may refine punctuation after the user is already
        // silent. The acoustic end is unchanged, so this must not postpone the
        // boundary that makes the first phrase immutable.
        XCTAssertEqual(
            accumulator.receive(
                "第一段训练，",
                isFinal: false,
                at: start.addingTimeInterval(0.7),
                speechSegmentStart: 0,
                speechSegmentEnd: 0.6
            ),
            "第一段训练，"
        )
        XCTAssertEqual(accumulator.speechActivityRevision, activityRevision)

        XCTAssertEqual(
            accumulator.receive(
                "第二段饮食",
                isFinal: false,
                at: start.addingTimeInterval(
                    SpeechTranscriptAccumulator.pauseBoundary + 0.05
                )
            ),
            "第一段训练，第二段饮食"
        )
    }

    func testSpeechAccumulatorDeduplicatesRepeatedFinalAndPreservesPunctuation() {
        var accumulator = SpeechTranscriptAccumulator()
        XCTAssertEqual(accumulator.receive("先做热身。", isFinal: true), "先做热身。")
        XCTAssertEqual(accumulator.receive("先做热身。", isFinal: true), "先做热身。")
        XCTAssertEqual(accumulator.receive("Then squat", isFinal: true), "先做热身。Then squat，")
        XCTAssertEqual(accumulator.commitCurrent(), "先做热身。Then squat，")
    }

    func testSpeechAccumulatorAddsPunctuationWhenSilenceCommitsPartial() {
        var accumulator = SpeechTranscriptAccumulator()
        XCTAssertEqual(accumulator.receive("先做热身", isFinal: false), "先做热身")
        XCTAssertEqual(
            accumulator.commitCurrent(addsPausePunctuation: true),
            "先做热身，"
        )
        XCTAssertEqual(accumulator.receive("再做深蹲", isFinal: false), "先做热身，再做深蹲")
    }

    func testSpeechAccumulatorCommitsUnfinalizedPartialWhenSpeechRestartsAfterPause() {
        var accumulator = SpeechTranscriptAccumulator()
        let start = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(
            accumulator.receive("今天练深蹲", isFinal: false, at: start),
            "今天练深蹲"
        )
        XCTAssertEqual(
            accumulator.receive(
                "五组",
                isFinal: false,
                at: start.addingTimeInterval(SpeechTranscriptAccumulator.pauseBoundary + 0.1)
            ),
            "今天练深蹲，五组"
        )
        XCTAssertEqual(
            accumulator.receive("五组五次", isFinal: true),
            "今天练深蹲，五组五次，"
        )
    }

    func testStoppingAndRestartingVoiceUsesCommittedDraftAsNewBaseline() {
        let state = makeListeningState(draft: "已有文字")
        state.speechInput?.transcript = "第一段"
        state.syncDraftFromSpeech()
        XCTAssertEqual(state.draft, "已有文字 第一段")

        state.speechInput?.transcript = ""
        state.syncDraftFromSpeech()
        state.draftBeforeSpeech = state.trimmedDraft
        state.speechInput?.transcript = "第二段"
        state.syncDraftFromSpeech()

        XCTAssertEqual(state.draft, "已有文字 第一段 第二段")
    }

    func testRepeatedPartialDoesNotPostponePauseBoundaryAndOverwriteEarlierWords() {
        var accumulator = SpeechTranscriptAccumulator()
        let start = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(
            accumulator.receive("先记录深蹲", isFinal: false, at: start),
            "先记录深蹲"
        )
        XCTAssertEqual(
            accumulator.receive(
                "先记录深蹲",
                isFinal: false,
                at: start.addingTimeInterval(0.7)
            ),
            "先记录深蹲"
        )
        XCTAssertEqual(
            accumulator.receive(
                "再记录硬拉",
                isFinal: false,
                at: start.addingTimeInterval(
                    SpeechTranscriptAccumulator.pauseBoundary + 0.1
                )
            ),
            "先记录深蹲，再记录硬拉"
        )
    }

    func testAcousticSegmentGapCommitsPriorPartialEvenWhenCallbacksAreClose() {
        var accumulator = SpeechTranscriptAccumulator()
        let start = Date(timeIntervalSince1970: 2000)

        _ = accumulator.receive(
            "第一段",
            isFinal: false,
            at: start,
            speechSegmentStart: 0,
            speechSegmentEnd: 0.6
        )
        XCTAssertEqual(
            accumulator.receive(
                "第二段",
                isFinal: false,
                at: start.addingTimeInterval(0.2),
                speechSegmentStart: 1.6,
                speechSegmentEnd: 2.1
            ),
            "第一段，第二段"
        )
    }
}
