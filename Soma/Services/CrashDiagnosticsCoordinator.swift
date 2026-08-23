import Foundation
import MetricKit
import UIKit

/// ADR 0095：哨兵只保留待关联上下文；只有 MetricKit 的 MXCrashDiagnostic 可以生成报告。
/// 总开关在高级设置里，关闭后只留盘不发送。
@MainActor
@Observable
final class CrashDiagnosticsCoordinator: NSObject {
    static let autoSendDefaultsKey = "diagnostics.autoSendCrashReports"
    static let shared = CrashDiagnosticsCoordinator()

    private let defaults: UserDefaults
    private let reports: DiagnosticReportStore
    private let logs: DiagnosticsLogStore
    private let mailer: DiagnosticReportMailer
    private var previousRun: AppRunSentinel.PreviousRun?
    private var hasActivated = false
    private var isFlushing = false
    /// 单测宿主是 App 本身，每轮测试结束都会被杀进程；测试里必须完全不上报。
    private let isSuppressed = AppRunSentinel.isRunningUnderTests

    private(set) var lastReportSummary: String?
    private(set) var pendingReportCount = 0

    init(
        defaults: UserDefaults = .standard,
        reports: DiagnosticReportStore = .shared,
        logs: DiagnosticsLogStore = .shared,
        mailer: DiagnosticReportMailer = DiagnosticReportMailer()
    ) {
        self.defaults = defaults
        self.reports = reports
        self.logs = logs
        self.mailer = mailer
        super.init()
        if defaults.object(forKey: Self.autoSendDefaultsKey) == nil {
            defaults.set(true, forKey: Self.autoSendDefaultsKey)
        }
    }

    var isAutoSendEnabled: Bool {
        get { defaults.bool(forKey: Self.autoSendDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.autoSendDefaultsKey) }
    }

    func activate(previousRun: AppRunSentinel.PreviousRun) {
        guard !isSuppressed, !hasActivated else { return }
        hasActivated = true
        self.previousRun = previousRun
        MXMetricManager.shared.add(self)
        purgeUnconfirmedReports()
        pendingReportCount = reports.pendingReports().count
        lastReportSummary = reports.latestReport().map(Self.summary(of:))
    }

    /// 启动后只清理旧哨兵标记并投递已有的系统确认报告，不查询业务数据库。
    func flushPendingReports() async {
        guard !isSuppressed, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        if let previousRun {
            if previousRun.endedUnexpectedly {
                logs.append(
                    category: "diagnostics",
                    message: "检测到上次运行未清位，仅保留上下文并等待 MetricKit 崩溃证据"
                )
            }
            AppRunSentinel.shared.clearPreviousRunMarkers()
        }
        await deliverPendingReports()
    }

    private func enqueueConfirmedCrash(
        diagnosis: CrashReportDiagnosis,
        context: CrashReportContext
    ) {
        guard CrashReportEligibility.isSystemConfirmed(source: diagnosis.source) else {
            logs.append(
                category: "diagnostics",
                message: "拒绝缺少 MetricKit 证据的崩溃报告"
            )
            return
        }
        let reportID = UUID()
        let createdAt = Date()
        let report = DiagnosticReport(
            id: reportID,
            createdAt: createdAt,
            subject: CrashReportComposer.subject(for: diagnosis),
            body: CrashReportComposer.body(
                reportID: reportID,
                createdAt: createdAt,
                diagnosis: diagnosis,
                environment: Self.environment(),
                context: context,
                recentLog: logs.recentText()
            ),
            evidenceSource: .metricKit
        )
        reports.save(report)
        pendingReportCount = reports.pendingReports().count
        lastReportSummary = Self.summary(of: report)
        DiagnosticsLogStore.shared.append(
            category: "diagnostics",
            message: "生成崩溃报告",
            fields: [
                "report_id": reportID.uuidString,
                "source": diagnosis.source,
                "headline": diagnosis.headline
            ]
        )
    }

    func deliverPendingReports() async {
        guard isAutoSendEnabled else { return }
        purgeUnconfirmedReports()
        for report in reports.pendingReports() {
            guard CrashReportEligibility.isSystemConfirmed(report: report) else {
                reports.remove(report.id)
                continue
            }
            guard report.deliveryAttemptCount
                < DiagnosticReportStore.maximumDeliveryAttempts
            else {
                continue
            }
            do {
                try await mailer.send(report)
                reports.remove(report.id)
                DiagnosticsLogStore.shared.append(
                    category: "diagnostics",
                    message: "崩溃报告已发送",
                    fields: ["report_id": report.id.uuidString]
                )
            } catch {
                var retried = report
                retried.deliveryAttemptCount += 1
                retried.lastError = error.localizedDescription
                reports.save(retried)
                DiagnosticsLogStore.shared.append(
                    category: "diagnostics",
                    message: "崩溃报告发送失败",
                    fields: [
                        "report_id": report.id.uuidString,
                        "attempt": "\(retried.deliveryAttemptCount)",
                        "error": error.localizedDescription
                    ]
                )
            }
        }
        pendingReportCount = reports.pendingReports().count
    }

    func latestReportText() -> String? {
        reports.latestReport()?.body
    }

    /// 丢弃排队中的报告。误判产生的报告会一直重试，用户需要一个立即停手的开关。
    func discardPendingReports() {
        reports.removeAll()
        pendingReportCount = 0
        lastReportSummary = nil
        logs.append(
            category: "diagnostics",
            message: "用户丢弃了全部待发送诊断报告"
        )
    }

    /// 旧版本可能已经把 sentinel 误判落盘；升级后在任何投递前直接清除。
    private func purgeUnconfirmedReports() {
        let unconfirmed = reports.pendingReports().filter {
            !CrashReportEligibility.isSystemConfirmed(report: $0)
        }
        guard !unconfirmed.isEmpty else { return }
        for report in unconfirmed {
            reports.remove(report.id)
        }
        logs.append(
            category: "diagnostics",
            message: "已清理缺少 MetricKit 证据的旧崩溃报告",
            fields: ["count": "\(unconfirmed.count)"]
        )
    }

    static func summary(of report: DiagnosticReport) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: report.createdAt)) · \(report.subject)"
    }

    private static func environment() -> CrashReportEnvironment {
        let device = UIDevice.current
        let available = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity
        return CrashReportEnvironment(
            version: AppBuildInfo.version,
            build: AppBuildInfo.build,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            deviceModel: Self.hardwareModel(),
            locale: Locale.current.identifier,
            thermalState: "\(ProcessInfo.processInfo.thermalState.rawValue)",
            availableDiskBytes: available.map(Int64.init),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private static func hardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(_SYS_NAMELEN)
            ) { String(cString: $0) }
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

extension CrashDiagnosticsCoordinator: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let diagnoses = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map(Self.diagnosis(from:))
        }
        guard !diagnoses.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let run = previousRun
            for diagnosis in diagnoses {
                enqueueConfirmedCrash(
                    diagnosis: diagnosis,
                    context: CrashReportContext(
                        sessionID: run?.sessionID,
                        turnID: run?.turnID,
                        lastActivity: run?.activity,
                        lastHeartbeat: run?.lastHeartbeat,
                        sessionMessages: [],
                        traceSpans: [],
                        traceSummary: nil
                    )
                )
            }
            previousRun = nil
            await deliverPendingReports()
        }
    }

    private nonisolated static func diagnosis(
        from crash: MXCrashDiagnostic
    ) -> CrashReportDiagnosis {
        CrashReportDiagnosis(
            source: "metrickit",
            headline: crash.exceptionType.map {
                "系统记录到崩溃（exception \($0.intValue)）"
            } ?? "系统记录到崩溃",
            terminationReason: crash.terminationReason,
            exceptionType: crash.exceptionType.map { "\($0.intValue)" },
            exceptionCode: crash.exceptionCode.map { "\($0.intValue)" },
            signal: crash.signal.map { "\($0.intValue)" },
            callStack: String(
                data: crash.callStackTree.jsonRepresentation(),
                encoding: .utf8
            )
        )
    }
}
