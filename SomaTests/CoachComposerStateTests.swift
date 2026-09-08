@testable import Soma
import XCTest

@MainActor
final class CoachComposerStateTests: XCTestCase {
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

    func testShortcutAutofillOnlyWhenDraftIsEmpty() throws {
        let recent = try XCTUnwrap(AgentInputShortcutStore.defaultShortcuts.first {
            $0.id == "shortcut_recent_review"
        })
        let nutrition = try XCTUnwrap(AgentInputShortcutStore.defaultShortcuts.first {
            $0.id == "shortcut_nutrition"
        })
        let state = CoachComposerState()
        state.toggleShortcut(recent)
        XCTAssertEqual(state.selectedShortcutID, recent.id)
        XCTAssertEqual(state.draft, recent.suggestedPrompt)
        state.toggleShortcut(recent)
        XCTAssertNil(state.selectedShortcutID)
        XCTAssertTrue(state.draft.isEmpty)

        state.draft = "已经写了"
        state.toggleShortcut(recent)
        XCTAssertEqual(state.draft, "已经写了")
        state.toggleShortcut(nutrition)
        XCTAssertEqual(state.draft, "已经写了")
        XCTAssertNil(nutrition.suggestedPrompt)
        XCTAssertNil(
            AgentInputShortcutStore.defaultShortcuts.first { $0.id == "shortcut_workout_log" }?
                .suggestedPrompt
        )

        let workout = try XCTUnwrap(AgentInputShortcutStore.defaultShortcuts.first {
            $0.id == "shortcut_workout_log"
        })
        state.toggleShortcut(nutrition)
        state.toggleShortcut(workout)
        XCTAssertEqual(state.selectedShortcutID, workout.id)
        XCTAssertEqual(state.draft, "已经写了")
        state.toggleShortcut(workout)
        XCTAssertNil(state.selectedShortcutID)
        state.draft = ""
        state.toggleShortcut(workout)
        XCTAssertEqual(state.selectedShortcutID, workout.id)
        XCTAssertTrue(state.draft.isEmpty)
    }

    func testSpeechAppendsToCurrentManualEdit() {
        let state = CoachComposerState()
        state.draft = "深蹲五组"
        state.appendSpeechSegment("每组五次", pause: 0.8)
        XCTAssertEqual(state.draft, "深蹲五组，每组五次")
        state.draft = "深蹲三组"
        state.appendSpeechSegment("重量六十公斤", pause: 2)
        XCTAssertEqual(state.draft, "深蹲三组。重量六十公斤")
    }

    func testDeletedAndSubmittedTextNeverReturns() {
        let state = CoachComposerState()
        state.appendSpeechSegment("今天训练")
        state.draft = ""
        state.appendSpeechSegment("明天休息")
        XCTAssertEqual(state.draft, "明天休息")
        state.clearAfterSubmission()
        state.appendSpeechSegment("记录午餐")
        XCTAssertEqual(state.draft, "记录午餐")
        state.prepareForSessionChange()
        state.appendSpeechSegment("新会话")
        XCTAssertEqual(state.draft, "新会话")
    }

    func testRepeatedSpokenPhrasesRemainLegitimateInput() {
        let state = CoachComposerState()
        state.appendSpeechSegment("再做一组")
        state.appendSpeechSegment("再做一组", pause: 0.8)
        XCTAssertEqual(state.draft, "再做一组，再做一组")
    }

    func testPunctuationAndEnglishWordBoundaries() {
        XCTAssertEqual(SpeechDraftAppend.append("下一项。", to: "完成！", pause: 3), "完成！下一项。")
        XCTAssertEqual(SpeechDraftAppend.append("，下一项", to: "完成，", pause: 1), "完成，下一项")
        XCTAssertEqual(SpeechDraftAppend.append("press", to: "bench", pause: 0.1), "bench press")
        XCTAssertEqual(SpeechDraftAppend.append("rest", to: "done", pause: 2), "done. rest")
        XCTAssertEqual(SpeechDraftAppend.append(" ", to: "手动文本", pause: 2), "手动文本")
    }
}
