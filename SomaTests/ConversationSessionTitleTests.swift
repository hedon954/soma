@testable import Soma
import XCTest

final class ConversationSessionTitleTests: XCTestCase {
    func testDefaultTitleUsesSessionDateWeekdayAndBusinessTimeZone() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let startedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-02T00:15:00+08:00")
        )

        let session = ConversationSession(
            startedAt: startedAt,
            businessTimeZoneIdentifier: zone.identifier
        )

        XCTAssertEqual(session.title, "09月02日 - 周三")
        XCTAssertTrue(session.isUsingDateTitle)
        XCTAssertNil(session.titleSourceRaw)
    }

    func testMessageDoesNotRenameSessionAndManualRenameDoesNotReorder() throws {
        let startedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-02T08:00:00+08:00")
        )
        let updatedAt = startedAt.addingTimeInterval(60)
        let session = ConversationSession(
            startedAt: startedAt,
            updatedAt: updatedAt,
            businessTimeZoneIdentifier: "Asia/Shanghai"
        )

        session.recordUserMessage("帮我分析卧推", at: updatedAt.addingTimeInterval(60))
        XCTAssertEqual(session.title, "09月02日 - 周三")
        XCTAssertEqual(session.updatedAt, updatedAt.addingTimeInterval(60))

        let beforeRename = session.updatedAt
        XCTAssertTrue(session.setManualTitle("  我的\n卧推复盘  "))
        XCTAssertEqual(session.title, "我的 卧推复盘")
        XCTAssertEqual(session.updatedAt, beforeRename)
        XCTAssertFalse(session.isUsingDateTitle)

        session.restoreDateTitle()
        XCTAssertEqual(session.title, "09月02日 - 周三")
        XCTAssertEqual(session.updatedAt, beforeRename)
        XCTAssertTrue(session.isUsingDateTitle)
    }

    func testDateTitleUsesStartedAtAcrossBusinessTimeZoneBoundary() throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-01T16:30:00Z")
        )
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        XCTAssertEqual(
            ConversationSession.dateTitle(for: instant, in: shanghai),
            "09月02日 - 周三"
        )
        XCTAssertEqual(
            ConversationSession.dateTitle(for: instant, in: utc),
            "09月01日 - 周二"
        )
    }

    func testLegacyArchivePreservesCompatibilityFieldWithoutAffectingTitle() throws {
        struct LegacySessionDTO: Encodable {
            var id: UUID
            var startedAt: Date
            var updatedAt: Date
            var title: String
            var titleSourceRaw: String?
        }
        let legacy = LegacySessionDTO(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_787_342_400),
            updatedAt: Date(timeIntervalSince1970: 1_787_342_460),
            title: "旧会话标题",
            titleSourceRaw: "generated"
        )

        let decoded = try JSONDecoder().decode(
            ConversationSessionDTO.self,
            from: JSONEncoder().encode(legacy)
        )
        let model = decoded.makeModel()

        XCTAssertEqual(model.title, "旧会话标题")
        XCTAssertEqual(model.titleSourceRaw, "generated")
        XCTAssertFalse(model.isUsingDateTitle)
    }
}
