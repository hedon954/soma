@testable import Soma
import XCTest

/// ADR 0083：本机诊断日志的格式稳定、密钥恒定脱敏、体积有上限。
final class DiagnosticsLogStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "soma-diagnostics-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLineCarriesCategoryMessageAndSortedFields() {
        let line = DiagnosticsLogStore.line(
            category: "workout-recording",
            message: "录像提前结束",
            fields: ["technical": "AVFoundationErrorDomain -11818", "cause": "存储不足"],
            at: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(line.contains("[workout-recording]"))
        XCTAssertTrue(line.contains("录像提前结束"))
        XCTAssertTrue(line.hasSuffix("\n"))
        let causeIndex = try? XCTUnwrap(line.range(of: "cause=")?.lowerBound)
        let technicalIndex = try? XCTUnwrap(line.range(of: "technical=")?.lowerBound)
        XCTAssertNotNil(causeIndex)
        XCTAssertNotNil(technicalIndex)
        if let causeIndex, let technicalIndex {
            XCTAssertLessThan(causeIndex, technicalIndex)
        }
    }

    func testApiKeysAndBearerHeadersAreRedacted() {
        XCTAssertEqual(
            DiagnosticsLogStore.redact("key=sk-abcdef1234567890 done"),
            "key=[已脱敏] done"
        )
        XCTAssertEqual(
            DiagnosticsLogStore.redact("Authorization: Bearer abc.def-123"),
            "[已脱敏]"
        )
        XCTAssertEqual(
            DiagnosticsLogStore.redact("api_key: 1234567890"),
            "[已脱敏]"
        )
    }

    func testInlineMediaPayloadIsRedacted() {
        let redacted = DiagnosticsLogStore.redact(
            "image=data:image/jpeg;base64,AAAABBBBCCCCDDDD tail"
        )

        XCTAssertEqual(redacted, "image=[已脱敏] tail")
    }

    func testOrdinaryChineseTextIsNotRedacted() {
        let text = "录像提前结束，原因是设备存储空间不足"

        XCTAssertEqual(DiagnosticsLogStore.redact(text), text)
    }

    func testAppendedLinesAreReadableInOrder() throws {
        let store = DiagnosticsLogStore(directory: directory)

        store.append(category: "lifecycle", message: "启动")
        store.append(category: "agent", message: "工具执行", fields: ["tool": "create_meal"])
        let text = store.recentText()

        XCTAssertTrue(text.contains("启动"))
        XCTAssertTrue(text.contains("tool=create_meal"))
        let launchIndex = try XCTUnwrap(text.range(of: "启动")?.lowerBound)
        let toolIndex = try XCTUnwrap(text.range(of: "工具执行")?.lowerBound)
        XCTAssertLessThan(launchIndex, toolIndex)
    }

    func testRotationKeepsStorageBounded() {
        let store = DiagnosticsLogStore(directory: directory, maximumFileBytes: 2048)
        let filler = String(repeating: "诊断", count: 200)

        for index in 0 ..< 60 {
            store.append(category: "stress", message: "\(index) \(filler)")
        }
        _ = store.recentText()

        XCTAssertLessThanOrEqual(store.storedByteCount(), 2048 * 3)
        XCTAssertTrue(store.recentText().contains("59"))
    }

    func testClearRemovesEverything() {
        let store = DiagnosticsLogStore(directory: directory)
        store.append(category: "lifecycle", message: "启动")
        _ = store.recentText()

        store.clear()

        XCTAssertEqual(store.storedByteCount(), 0)
        XCTAssertTrue(store.recentText().isEmpty)
    }

    func testAsyncReadAndClearPreserveOrderingAndRemoveFiles() async {
        let store = DiagnosticsLogStore(directory: directory)
        store.append(category: "lifecycle", message: "启动")
        store.append(category: "agent", message: "完成")

        let text = await store.recentTextAsync()
        XCTAssertTrue(text.contains("启动"))
        XCTAssertTrue(text.contains("完成"))

        await store.clearAsync()

        XCTAssertEqual(store.storedByteCount(), 0)
        let clearedText = await store.recentTextAsync()
        XCTAssertTrue(clearedText.isEmpty)
    }
}
