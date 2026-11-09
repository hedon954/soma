@testable import Soma
import XCTest

final class BodyMassHistoryRowPresentationTests: XCTestCase {
    func testAccessibilityLinesKeepWeightAndBodyFatAsSingleLines() throws {
        let date = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 0, minute: 0))
        )
        let lines = BodyMassHistoryRowPresentation.accessibilityLines(
            date: date,
            weight: 70.9,
            bodyFat: 18.0,
            source: .keep,
            isHealthImported: true
        )
        XCTAssertEqual(lines.weightLine, "70.9\u{00A0}kg")
        XCTAssertEqual(lines.bodyFatLine, "体脂率\u{00A0}18.0%")
        XCTAssertEqual(lines.sourceCaption, "Keep")
        XCTAssertFalse(lines.weightLine?.contains("\n") == true)
        XCTAssertEqual(lines.sampleTime, BodyMassHistoryRowPresentation.sampleTimeText(date))
        XCTAssertFalse(lines.sampleTime.contains("2026"))
        XCTAssertFalse(lines.sampleTime.contains("8月11日") || lines.sampleTime.contains("8/11"))
    }

    func testBodyFatOnlyAndLongUnknownSource() {
        let fatOnly = BodyMassHistoryRowPresentation.accessibilityLines(
            date: .now,
            weight: nil,
            bodyFat: 18.6,
            source: .keep,
            isHealthImported: true
        )
        XCTAssertNil(fatOnly.weightLine)
        XCTAssertEqual(fatOnly.bodyFatLine, "体脂率\u{00A0}18.6%")

        let longName = "超长厂商名称 Acme Smart Body Composition Scale Pro Max"
        let unknown = BodyMassHistoryRowPresentation.accessibilityLines(
            date: .now,
            weight: 72.1,
            bodyFat: nil,
            source: .unknown(displayName: longName),
            unknownSourceName: longName,
            isHealthImported: true
        )
        XCTAssertEqual(unknown.sourceCaption, BodyMassKnownSource.unknown(displayName: longName).listCaption)
        XCTAssertEqual(unknown.weightLine, "72.1\u{00A0}kg")
        XCTAssertNil(unknown.bodyFatLine)
    }

    func testManualSourceCaption() {
        let lines = BodyMassHistoryRowPresentation.accessibilityLines(
            date: .now,
            weight: 71.8,
            bodyFat: 17.5,
            source: nil,
            isHealthImported: false
        )
        XCTAssertEqual(lines.sourceCaption, "手动")
        XCTAssertEqual(lines.weightLine, "71.8\u{00A0}kg")
        XCTAssertEqual(lines.bodyFatLine, "体脂率\u{00A0}17.5%")
    }
}
