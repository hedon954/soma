@testable import Soma
import XCTest

final class DurationSecondsFormatTests: XCTestCase {
    func testDisplayOmitsZeroUnits() {
        XCTAssertEqual(DurationSecondsFormat.display(0), "0秒")
        XCTAssertEqual(DurationSecondsFormat.display(45), "45秒")
        XCTAssertEqual(DurationSecondsFormat.display(60), "1分")
        XCTAssertEqual(DurationSecondsFormat.display(90), "1分30秒")
        XCTAssertEqual(DurationSecondsFormat.display(1800), "30分")
        XCTAssertEqual(DurationSecondsFormat.display(3600), "1时")
        XCTAssertEqual(DurationSecondsFormat.display(3661), "1时1分1秒")
    }

    func testParseAcceptsBareSecondsAndChineseUnits() {
        XCTAssertEqual(DurationSecondsFormat.parse("1800"), 1800)
        XCTAssertEqual(DurationSecondsFormat.parse("30分"), 1800)
        XCTAssertEqual(DurationSecondsFormat.parse("1时30分"), 5400)
        XCTAssertEqual(DurationSecondsFormat.parse("1小时 1分钟 1秒"), 3661)
        XCTAssertEqual(DurationSecondsFormat.parse(" 45 秒 "), 45)
        XCTAssertNil(DurationSecondsFormat.parse(""))
        XCTAssertNil(DurationSecondsFormat.parse("abc"))
    }
}
