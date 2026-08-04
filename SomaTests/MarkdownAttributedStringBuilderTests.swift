@testable import Soma
import XCTest

final class MarkdownAttributedStringBuilderTests: XCTestCase {
    func testPreservesParagraphBreaks() {
        let markdown = "第一段说明。\n\n第二段继续。"
        let rendered = MarkdownAttributedStringBuilder.plainString(from: markdown)

        XCTAssertTrue(rendered.contains("第一段说明。"))
        XCTAssertTrue(rendered.contains("第二段继续。"))
        XCTAssertTrue(
            rendered.contains("\n"),
            "paragraph breaks must survive full markdown rendering; got: \(rendered)"
        )
        XCTAssertFalse(
            rendered.contains("第一段说明。第二段继续。"),
            "paragraphs must not glue together; got: \(rendered)"
        )
    }

    func testPreservesOrderedListBreaksAndMarkers() {
        let markdown = """
        当前模板：
        1. 杠铃深蹲 5×5 50kg 60s
        2. 杠铃卧推 5×5 50kg 60s
        3. 罗马尼亚硬拉 4×5 50kg 60s
        """
        let rendered = MarkdownAttributedStringBuilder.plainString(from: markdown)

        XCTAssertTrue(rendered.contains("1. "))
        XCTAssertTrue(rendered.contains("2. "))
        XCTAssertTrue(rendered.contains("3. "))
        XCTAssertTrue(rendered.contains("杠铃深蹲"))
        XCTAssertTrue(rendered.contains("杠铃卧推"))
        XCTAssertFalse(
            rendered.contains("50kg 60s2"),
            "list items must not glue; got: \(rendered)"
        )
        XCTAssertFalse(
            rendered.contains("间歇1杠铃"),
            "ordered markers must not collapse into previous text; got: \(rendered)"
        )
    }

    func testPreservesUnorderedListBreaks() {
        let markdown = """
        注意：
        - 脚掌稳定
        - 膝盖跟随脚尖
        - 躯干保持张力
        """
        let rendered = MarkdownAttributedStringBuilder.plainString(from: markdown)

        XCTAssertTrue(rendered.contains("• ") || rendered.contains("- "))
        XCTAssertTrue(rendered.contains("脚掌稳定"))
        XCTAssertTrue(rendered.contains("膝盖跟随脚尖"))
        XCTAssertTrue(
            rendered.contains("\n"),
            "unordered list items must break lines; got: \(rendered)"
        )
        XCTAssertFalse(
            rendered.contains("脚掌稳定膝盖跟随脚尖"),
            "unordered items must not glue; got: \(rendered)"
        )
    }

    func testKeepsInlineEmphasis() {
        let markdown = "已更新 **周训练力量一**，引体向上已移除。"
        let attributed = MarkdownAttributedStringBuilder.attributedString(from: markdown)
        let rendered = attributed.string

        XCTAssertTrue(rendered.contains("周训练力量一"))
        XCTAssertFalse(rendered.contains("**"))
    }
}
