@testable import Soma
import XCTest

final class CoachProgressReliabilityTests: XCTestCase {
    @MainActor
    func testConcurrentDeliveryRequestsSendConfirmedReportOnce() async throws {
        let name = "test.soma.delivery.\(UUID())"
        let folder = FileManager.default.temporaryDirectory.appending(path: name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: name)
        }
        let reports = DiagnosticReportStore(directory: folder)
        var report = DiagnosticReport(subject: "合成诊断", body: "合成报告", evidenceSource: .metricKit)
        report.eventKey = "synthetic-crash-event"
        reports.save(report)
        let transport = CountingDiagnosticTransport()
        let coordinator = CrashDiagnosticsCoordinator(defaults: defaults, reports: reports, mailer: .init(
            credentialsProvider: { .init(senderAddress: "test@example.invalid", smtpAuthorizationCode: "test") },
            transport: transport
        ))
        async let first: Void = coordinator.deliverPendingReports()
        async let second: Void = coordinator.deliverPendingReports()
        _ = await (first, second)
        let count = await transport.count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(reports.pendingReports().isEmpty)

        // 模拟退出发生在回执保存后、待发文件清理前。
        reports.save(report)
        let restarted = CrashDiagnosticsCoordinator(defaults: defaults, reports: reports, mailer: .init(
            credentialsProvider: { .init(senderAddress: "test@example.invalid", smtpAuthorizationCode: "test") },
            transport: transport
        ))
        await restarted.deliverPendingReports()
        let countAfterRestart = await transport.count
        XCTAssertEqual(countAfterRestart, 1)
        XCTAssertTrue(reports.pendingReports().isEmpty)
    }
}

private actor CountingDiagnosticTransport: FeedbackSMTPTransport {
    var count = 0
    func send(message _: Data, sender _: String, recipient _: String, authorizationCode _: String) async throws {
        count += 1
        await Task.yield()
    }
}
