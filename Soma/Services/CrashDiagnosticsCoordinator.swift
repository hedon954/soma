import Foundation
import MetricKit
import SwiftData
import UIKit

/// ADR 0083：启动时判断上一次运行是否异常终止，把崩溃上下文拼成报告并静默发送。
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
        pendingReportCount = reports.pendingReports().count
        lastReportSummary = reports.latestReport().map(Self.summary(of:))
    }

    /// 由持有 `ModelContext` 的根视图调用：补齐崩溃 session 上下文，然后落盘并尝试发送。
    func flushPendingReports(in context: ModelContext) async {
        guard !isSuppressed, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        if let previousRun {
            self.previousRun = nil
            if CrashReportEligibility.shouldReportSentinelTermination(previousRun) {
                enqueueSentinelReport(previousRun, in: context)
            } else if previousRun.endedUnexpectedly {
                logs.append(
                    category: "diagnostics",
                    message: "上次运行附着调试器结束，不作为崩溃上报"
                )
            }
            AppRunSentinel.shared.clearPreviousRunMarkers()
        }
        await deliverPendingReports()
    }

    private func enqueueSentinelReport(
        _ previousRun: AppRunSentinel.PreviousRun,
        in context: ModelContext
    ) {
        let diagnosis = CrashReportDiagnosis(
            source: "sentinel",
            headline: "上次前台运行被异常终止",
            terminationReason: "启动哨兵未被正常清位；MetricKit 崩溃诊断可能随后补充",
            exceptionType: nil,
            exceptionCode: nil,
            signal: nil,
            callStack: nil
        )
        enqueue(
            diagnosis: diagnosis,
            context: CrashDiagnosticsContextBuilder.build(
                sessionID: previousRun.sessionID,
                turnID: previousRun.turnID,
                lastActivity: previousRun.activity,
                lastHeartbeat: previousRun.lastHeartbeat,
                in: context
            )
        )
    }

    func enqueue(
        diagnosis: CrashReportDiagnosis,
        context: CrashReportContext
    ) {
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
            )
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
        for report in reports.pendingReports() {
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
            for diagnosis in diagnoses {
                enqueue(
                    diagnosis: diagnosis,
                    context: CrashReportContext(
                        sessionID: previousRun?.sessionID,
                        turnID: previousRun?.turnID,
                        lastActivity: previousRun?.activity,
                        lastHeartbeat: previousRun?.lastHeartbeat,
                        sessionMessages: [],
                        traceSpans: [],
                        traceSummary: nil
                    )
                )
            }
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

/// 崩溃报告的 session 上下文读取。查询与 UI 无关，单独放一层便于复用与测试。
@MainActor
enum CrashDiagnosticsContextBuilder {
    static let maximumMessages = 40
    static let maximumMessageCharacters = 600
    static let maximumSpans = 24
    static let maximumSpanCharacters = 1200

    static func build(
        sessionID: UUID?,
        turnID: UUID?,
        lastActivity: String?,
        lastHeartbeat: Date?,
        in context: ModelContext
    ) -> CrashReportContext {
        var messages: [String] = []
        if let sessionID {
            let descriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.date)]
            )
            let fetched = (try? context.fetch(descriptor)) ?? []
            messages = fetched.suffix(maximumMessages).map(line(for:))
        }

        var spans: [String] = []
        var traceSummary: String?
        if let trace = latestTrace(turnID: turnID, sessionID: sessionID, in: context) {
            traceSummary = [
                "id=\(trace.id.uuidString)",
                "status=\(trace.statusRaw)",
                "provider=\(trace.provider)",
                "model=\(trace.model)",
                "attempt=\(trace.attemptNumber)",
                "error=\(trace.errorMessage ?? "none")"
            ].joined(separator: " ")
            spans = trace.spans.suffix(maximumSpans).map(line(for:))
        }

        return CrashReportContext(
            sessionID: sessionID,
            turnID: turnID,
            lastActivity: lastActivity,
            lastHeartbeat: lastHeartbeat,
            sessionMessages: messages,
            traceSpans: spans,
            traceSummary: traceSummary
        )
    }

    private static func latestTrace(
        turnID: UUID?,
        sessionID: UUID?,
        in context: ModelContext
    ) -> AgentTrace? {
        if let turnID {
            var descriptor = FetchDescriptor<AgentTrace>(
                predicate: #Predicate { $0.turnID == turnID },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let trace = (try? context.fetch(descriptor))?.first {
                return trace
            }
        }
        guard sessionID != nil else { return nil }
        var descriptor = FetchDescriptor<AgentTrace>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func line(for message: CoachMessage) -> String {
        let role = message.isFromCoach ? "assistant" : "user"
        let text = message.text.isEmpty ? "（无正文）" : message.text
        return "[\(role)] \(message.date.ISO8601Format()) \(String(text.prefix(maximumMessageCharacters)))"
    }

    private static func line(for span: AgentTraceSpan) -> String {
        [
            "step=\(span.step.map(String.init) ?? "none")",
            "kind=\(span.kind.rawValue)",
            "title=\(span.title)",
            "status=\(span.status.rawValue)",
            "input=\(String((span.input ?? "none").prefix(maximumSpanCharacters)))",
            "output=\(String((span.output ?? "none").prefix(maximumSpanCharacters)))",
            "metadata=\(span.metadata ?? "none")",
            "error=\(span.errorMessage ?? "none")"
        ].joined(separator: " ")
    }
}
