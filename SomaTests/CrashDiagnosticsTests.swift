@testable import Soma
import XCTest

/// ADR 0083：崩溃哨兵、报告拼装、留盘重试与邮件封装。
final class CrashDiagnosticsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        suiteName = "soma.crash.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory
            .appending(path: "soma-reports-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 哨兵

    @MainActor
    func testCleanForegroundExitIsNotReportedAsCrash() {
        let first = AppRunSentinel(defaults: defaults)
        first.beginRun(version: "1.0", build: "1")
        first.markForegroundActive()
        first.markForegroundEnded()

        let second = AppRunSentinel(defaults: defaults)
        let previous = second.beginRun(version: "1.0", build: "1")

        XCTAssertFalse(previous.endedUnexpectedly)
    }

    @MainActor
    func testForegroundRunWithoutExitIsReportedAsUnexpected() {
        let first = AppRunSentinel(defaults: defaults)
        first.beginRun(version: "1.0", build: "1")
        first.markForegroundActive()

        let second = AppRunSentinel(defaults: defaults)
        let previous = second.beginRun(version: "1.1", build: "2")

        XCTAssertTrue(previous.endedUnexpectedly)
        XCTAssertEqual(previous.version, "1.0")
        XCTAssertEqual(previous.build, "1")
    }

    @MainActor
    func testRecordedActivitySurvivesIntoNextRun() {
        let sessionID = UUID()
        let turnID = UUID()
        let first = AppRunSentinel(defaults: defaults)
        first.beginRun(version: "1.0", build: "1")
        first.markForegroundActive()
        first.recordActivity(
            sessionID: sessionID,
            turnID: turnID,
            activity: "agent-turn backend=local"
        )

        let previous = AppRunSentinel(defaults: defaults)
            .beginRun(version: "1.0", build: "1")

        XCTAssertEqual(previous.sessionID, sessionID)
        XCTAssertEqual(previous.turnID, turnID)
        XCTAssertEqual(previous.activity, "agent-turn backend=local")
        XCTAssertNotNil(previous.lastHeartbeat)
    }

    /// 单测宿主是 App 本身，测试结束进程被直接杀掉。哨兵必须在测试进程里整体停用，
    /// 否则每跑一次测试就会在下次启动发出一封假崩溃报告。
    @MainActor
    func testSentinelIsInertInsideTestProcess() {
        XCTAssertTrue(AppRunSentinel.isRunningUnderTests)

        let sentinel = AppRunSentinel(defaults: defaults, isSuppressed: true)
        sentinel.beginRun(version: "1.0", build: "1")
        sentinel.markForegroundActive()
        sentinel.recordActivity(sessionID: UUID(), turnID: nil, activity: "agent-turn")

        let next = AppRunSentinel(defaults: defaults)
        let previous = next.beginRun(version: "1.0", build: "1")
        XCTAssertFalse(previous.endedUnexpectedly)
        XCTAssertNil(previous.activity)
    }

    /// BUG 0032：哨兵只能保留上下文，任何未清位、强杀或调试器结束都不是崩溃证据。
    /// 只有系统 MetricKit 的 MXCrashDiagnostic 可以生成并投递崩溃报告。
    @MainActor
    func testOnlyMetricKitEvidenceMayGenerateCrashReport() {
        XCTAssertFalse(CrashReportEligibility.isSystemConfirmed(source: "sentinel"))
        XCTAssertFalse(CrashReportEligibility.isSystemConfirmed(source: "watchdog"))
        XCTAssertTrue(CrashReportEligibility.isSystemConfirmed(source: "metrickit"))

        let legacy = DiagnosticReport(subject: "旧误报", body: "无证据来源")
        let confirmed = DiagnosticReport(
            subject: "系统崩溃",
            body: "MetricKit 证据",
            evidenceSource: .metricKit
        )
        XCTAssertFalse(CrashReportEligibility.isSystemConfirmed(report: legacy))
        XCTAssertTrue(CrashReportEligibility.isSystemConfirmed(report: confirmed))
    }

    @MainActor
    func testSecondLaunchAfterCrashDoesNotRepeatTheFinding() {
        let first = AppRunSentinel(defaults: defaults)
        first.beginRun(version: "1.0", build: "1")
        first.markForegroundActive()

        let second = AppRunSentinel(defaults: defaults)
        XCTAssertTrue(second.beginRun(version: "1.0", build: "1").endedUnexpectedly)
        let third = AppRunSentinel(defaults: defaults)
        XCTAssertFalse(third.beginRun(version: "1.0", build: "1").endedUnexpectedly)
    }

    // MARK: - 报告拼装

    func testBodyContainsEveryRequiredSection() {
        let body = CrashReportComposer.body(
            reportID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            diagnosis: diagnosis(),
            environment: environment(),
            context: context(),
            recentLog: "2026-08-20T00:00:00Z [agent] LLM 调用 tools=create_meal"
        )

        for header in [
            "## 概要",
            "## 运行环境",
            "## 崩溃上下文",
            "## Session 消息",
            "## 最后一次执行过程",
            "## 调用栈",
            "## 最近诊断日志"
        ] {
            XCTAssertTrue(body.contains(header), "缺少段落 \(header)")
        }
        XCTAssertTrue(body.contains("create_meal"))
        XCTAssertTrue(body.contains("虚构午餐"))
    }

    func testBodyRedactsCredentialsFromLogs() {
        let body = CrashReportComposer.body(
            reportID: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            diagnosis: diagnosis(),
            environment: environment(),
            context: context(),
            recentLog: "Authorization: Bearer abc.def-1234567890"
        )

        XCTAssertFalse(body.contains("abc.def-1234567890"))
        XCTAssertTrue(body.contains("[已脱敏]"))
    }

    func testTruncationKeepsTheMostRecentTail() {
        let text = (0 ..< 5000).map(String.init).joined(separator: ",")
        let truncated = CrashReportComposer.truncate(text, to: 400)

        XCTAssertLessThanOrEqual(truncated.count, 400)
        XCTAssertTrue(truncated.hasPrefix("…（已截断更早内容）"))
        XCTAssertTrue(truncated.hasSuffix("4999"))
    }

    func testSubjectNamesTheDiagnosis() {
        XCTAssertEqual(
            CrashReportComposer.subject(for: diagnosis()),
            "Soma 崩溃诊断 · 系统记录到崩溃（exception 1）"
        )
    }

    // MARK: - 留盘与重试

    func testPendingReportsAreOrderedAndCappedAtFive() {
        let store = DiagnosticReportStore(directory: directory)
        for index in 0 ..< 8 {
            store.save(DiagnosticReport(
                createdAt: Date(timeIntervalSince1970: Double(index)),
                subject: "报告 \(index)",
                body: "正文 \(index)"
            ))
        }

        let pending = store.pendingReports()

        XCTAssertEqual(pending.count, DiagnosticReportStore.maximumRetainedReports)
        XCTAssertEqual(pending.map(\.subject), [
            "报告 3", "报告 4", "报告 5", "报告 6", "报告 7"
        ])
        XCTAssertEqual(store.latestReport()?.subject, "报告 7")
    }

    func testSavingRetryKeepsSingleRecordAndCountsAttempts() {
        let store = DiagnosticReportStore(directory: directory)
        var report = DiagnosticReport(subject: "报告", body: "正文")
        store.save(report)
        report.deliveryAttemptCount += 1
        report.lastError = "网络不可用"
        store.save(report)

        let pending = store.pendingReports()

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.deliveryAttemptCount, 1)
        XCTAssertEqual(pending.first?.lastError, "网络不可用")
    }

    func testRemovingDeliveredReportEmptiesTheQueue() {
        let store = DiagnosticReportStore(directory: directory)
        let report = DiagnosticReport(subject: "报告", body: "正文")
        store.save(report)

        store.remove(report.id)

        XCTAssertTrue(store.pendingReports().isEmpty)
        XCTAssertNil(store.latestReport())
    }

    // MARK: - 邮件封装

    func testMailMessageCarriesSubjectAndTextAttachment() throws {
        let report = DiagnosticReport(
            subject: "Soma 崩溃诊断 · 测试",
            body: "## 概要\n报告正文"
        )
        let data = DiagnosticReportMailer.mailMessage(
            report: report,
            sender: "sender@qq.com"
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("From: sender@qq.com"))
        XCTAssertTrue(text.contains(
            "To: \(FeedbackMailConfiguration.recipient)"
        ))
        XCTAssertTrue(text.contains("Subject: =?UTF-8?B?"))
        XCTAssertTrue(text.contains("multipart/mixed"))
        XCTAssertTrue(text.contains(
            "filename=\"soma-crash-\(report.id.uuidString.lowercased()).txt\""
        ))
    }

    func testOversizedBodyIsTrimmedBelowAttachmentLimit() {
        let body = String(repeating: "诊断", count: 900_000)

        let trimmed = DiagnosticReportMailer.trimmedAttachmentBody(body)

        XCTAssertLessThanOrEqual(
            Data(trimmed.utf8).count,
            DiagnosticReportMailer.maximumAttachmentBytes
                + "…（超出邮件体积上限，已截断更早内容）\n".utf8.count
        )
        XCTAssertTrue(trimmed.hasPrefix("…（超出邮件体积上限，已截断更早内容）"))
    }

    func testUserFeedbackLimitDoesNotConstrainDiagnosticReports() {
        XCTAssertGreaterThan(
            CrashReportComposer.maximumBodyCharacters,
            FeedbackSubmissionPolicy.maximumMessageCharacters
        )
    }

    // MARK: - Fixtures

    private func diagnosis() -> CrashReportDiagnosis {
        CrashReportDiagnosis(
            source: "metrickit",
            headline: "系统记录到崩溃（exception 1）",
            terminationReason: "Namespace SIGNAL, Code 11",
            exceptionType: "1",
            exceptionCode: "0",
            signal: "11",
            callStack: "0 Soma 0x0000 main"
        )
    }

    private func environment() -> CrashReportEnvironment {
        CrashReportEnvironment(
            version: "0.0.6",
            build: "8",
            systemName: "iOS",
            systemVersion: "18.0",
            deviceModel: "iPhone17,1",
            locale: "zh_CN",
            thermalState: "0",
            availableDiskBytes: 1_073_741_824,
            isLowPowerMode: false
        )
    }

    private func context() -> CrashReportContext {
        CrashReportContext(
            sessionID: UUID(),
            turnID: UUID(),
            lastActivity: "agent-turn backend=local",
            lastHeartbeat: Date(timeIntervalSince1970: 1_700_000_000),
            sessionMessages: ["[user] 2026-08-20T00:00:00Z 记录虚构午餐"],
            traceSpans: ["step=1 kind=tool title=创建饮食记录 status=succeeded"],
            traceSummary: "id=abc status=failed provider=虚构供应商 model=test"
        )
    }
}
