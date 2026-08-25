@testable import Soma
import XCTest

final class CoachResponseDocumentTests: XCTestCase {
    func testCompletedTextRenderCachesHeightByWidthScaleAndDynamicType() {
        let render = CoachCompletedTextRender(NSAttributedString(string: "虚构回复"))

        XCTAssertNil(render.measuredHeight(
            width: 320,
            scale: 3,
            contentSizeCategory: .large
        ))
        render.storeMeasuredHeight(
            480,
            width: 320,
            scale: 3,
            contentSizeCategory: .large
        )

        XCTAssertEqual(render.measuredHeight(
            width: 320,
            scale: 3,
            contentSizeCategory: .large
        ), 480)
        XCTAssertNil(render.measuredHeight(
            width: 321,
            scale: 3,
            contentSizeCategory: .large
        ))
        XCTAssertNil(render.measuredHeight(
            width: 320,
            scale: 3,
            contentSizeCategory: .accessibilityLarge
        ))
    }

    func testPreparesLargeMarkdownDocumentOffMainWithoutDroppingBlocks() async throws {
        let markdown = (0 ..< 240).map {
            PerformanceTestFixture.streamDelta($0, scenario: .markdownCompletion)
        }.joined()

        let preparation = try await Task.detached {
            try CoachTextRenderPreparation.make(for: markdown)
        }.value

        XCTAssertEqual(preparation.document.blocks.count, 720)
        XCTAssertEqual(
            preparation.document.blocks.first,
            .heading(level: 2, text: "第 1 段虚构复盘")
        )
        XCTAssertEqual(
            preparation.document.blocks.last,
            .unorderedList(["训练容量：保持可审查", "恢复安排：依据用户事实"])
        )
    }

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
