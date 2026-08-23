@testable import Soma
import XCTest

final class CoachResponseDocumentTests: XCTestCase {
    func testParsesControlledCoachMarkdownLayout() {
        let document = CoachResponseDocument.parse(
            """
            很棒的训练。下面是本次分析。

            ---

            ## 建议
            - 明天安排轻量恢复。
            - 保持蛋白质摄入。
            """
        )

        XCTAssertEqual(
            document.blocks,
            [
                .paragraph("很棒的训练。下面是本次分析。"),
                .divider,
                .heading(level: 2, text: "建议"),
                .unorderedList([
                    "明天安排轻量恢复。",
                    "保持蛋白质摄入。"
                ])
            ]
        )
    }

    func testKeepsUnknownMarkdownAsReadableParagraphs() {
        let document = CoachResponseDocument.parse(
            "第一行\n第二行\n\n普通结尾"
        )

        XCTAssertEqual(
            document.blocks,
            [
                .paragraph("第一行 第二行"),
                .paragraph("普通结尾")
            ]
        )
    }

    func testParsesOrderedListWithoutCreatingArbitraryComponents() {
        let document = CoachResponseDocument.parse(
            """
            ### 下一步
            1. 确认当前计划。
            2. 记录下一次训练。
            """
        )

        XCTAssertEqual(
            document.blocks,
            [
                .heading(level: 3, text: "下一步"),
                .orderedList(["确认当前计划。", "记录下一次训练。"])
            ]
        )
    }
}
