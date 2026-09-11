@testable import Soma
import SwiftUI
import XCTest

@MainActor
final class CoachDraftEditorTests: XCTestCase {
    func testEmptyAndShortTextShareOneLineHeightAndPlaceholderCannotWrap() {
        let view = CoachDraftEditor()
        let emptyHeight = view.measuredHeight(width: 235)
        XCTAssertEqual(emptyHeight + 2 * CoachDraftEditor.verticalInset, 44, accuracy: 1)
        for text in ["你好你好你好。", "今天训练十分钟", "hello world"] {
            view.text = text
            XCTAssertEqual(view.measuredHeight(width: 235), emptyHeight, accuracy: 1, text)
            XCTAssertFalse(view.isScrollEnabled)
        }
    }

    func testActualWidthControlsWrapAndReturnAddsALine() {
        let view = CoachDraftEditor()
        view.text = "今天训练之后做一会拉伸"
        let wide = view.measuredHeight(width: 320)
        let narrow = view.measuredHeight(width: 150)
        XCTAssertGreaterThan(narrow, wide + 10)
        view.text = "第一行"
        let single = view.measuredHeight(width: 235)
        view.text = "第一行\n"
        XCTAssertGreaterThan(view.measuredHeight(width: 235), single + 10)
        XCTAssertEqual(view.returnKeyType, .default)
    }

    func testLongTextCapsAtFiveLinesAndBecomesScrollableWithoutLosingText() throws {
        let view = CoachDraftEditor()
        let text = String(repeating: "一行训练说明\n", count: 20)
        view.text = text
        let line = try XCTUnwrap(view.font).lineHeight
        let height = view.measuredHeight(width: 235)
        XCTAssertLessThanOrEqual(height, ceil(5 * line))
        XCTAssertTrue(view.isScrollEnabled)
        XCTAssertEqual(view.text, text)
        view.text = "完成"
        XCTAssertEqual(view.measuredHeight(width: 235) + 2 * CoachDraftEditor.verticalInset, 44, accuracy: 1)
        XCTAssertFalse(view.isScrollEnabled)
    }

    func testRenderNeverEchoesAsUserEditAndPreservesSelection() {
        let view = CoachDraftEditor()
        var userChanges: [String] = []
        let coordinator = CoachDraftTextView.Coordinator(
            onTextChange: { userChanges.append($0) }, isFocused: .constant(false)
        )
        view.delegate = coordinator
        coordinator.render("深蹲五次", in: view)
        view.selectedRange = NSRange(location: 1, length: 1)
        coordinator.render("深蹲五次再做一组", in: view)
        XCTAssertEqual(view.selectedRange, NSRange(location: 1, length: 1))
        XCTAssertTrue(userChanges.isEmpty)
        view.text = "深蹲六次再做一组"
        coordinator.textViewDidChange(view)
        XCTAssertEqual(userChanges, ["深蹲六次再做一组"])
        XCTAssertTrue(view.isEditable)
    }

    func testMarkedChineseTextIsNotOverwrittenByRecognitionRendering() {
        let view = CoachDraftEditor()
        let coordinator = CoachDraftTextView.Coordinator(onTextChange: { _ in }, isFocused: .constant(false))
        coordinator.render("深", in: view)
        view.setMarkedText("dun", selectedRange: NSRange(location: 3, length: 0))
        let composing = view.text
        coordinator.render("深蹲五次", in: view)
        XCTAssertEqual(view.text, composing)
        view.unmarkText()
        coordinator.render("深蹲五次", in: view)
        XCTAssertEqual(view.text, "深蹲五次")
    }
}
