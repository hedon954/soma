import Foundation

/// ADR 0095：这里维护前台运行哨兵，只用于在 MetricKit 后续给出 MXCrashDiagnostic 时关联上下文。
/// 哨兵未清位可能来自崩溃、系统强杀、模拟器停进程或安装替换，本身绝不是崩溃证据。
///
/// 哨兵同时保存最后活跃的 session 与 turn，让崩溃报告能定位到具体上下文。
@MainActor
final class AppRunSentinel {
    static let shared = AppRunSentinel(
        isSuppressed: AppRunSentinel.isRunningUnderTests
    )

    private enum Key {
        static let foregroundRunActive = "diagnostics.foregroundRunActive"
        static let lastRunVersion = "diagnostics.lastRunVersion"
        static let lastRunBuild = "diagnostics.lastRunBuild"
        static let lastRunUnderDebugger = "diagnostics.lastRunUnderDebugger"
        static let lastHeartbeat = "diagnostics.lastHeartbeat"
        static let lastSessionID = "diagnostics.lastSessionID"
        static let lastTurnID = "diagnostics.lastTurnID"
        static let lastActivity = "diagnostics.lastActivity"
    }

    struct PreviousRun: Equatable, Sendable {
        var endedUnexpectedly: Bool
        var version: String?
        var build: String?
        var lastHeartbeat: Date?
        var sessionID: UUID?
        var turnID: UUID?
        var activity: String?
        /// 调试器结束进程和真实崩溃在哨兵上无法区分，需要单独记住。
        var wasUnderDebugger = false
    }

    /// 单测宿主就是 App 本身，测试结束时进程被直接杀掉，哨兵会把它读成崩溃。
    /// 测试进程里完全关闭崩溃诊断，既不置位也不上报。
    nonisolated static var isRunningUnderTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    /// Xcode 里按停止按钮和崩溃一样会留下哨兵，附着调试器的运行不作为崩溃证据。
    nonisolated static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&name, u_int(name.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    private let defaults: UserDefaults
    private let isSuppressed: Bool
    private(set) var previousRun: PreviousRun?

    init(
        defaults: UserDefaults = .standard,
        isSuppressed: Bool = false
    ) {
        self.defaults = defaults
        self.isSuppressed = isSuppressed
    }

    /// 只在启动时调用一次。返回上一次运行的摘要，并把哨兵重置到本次运行。
    @discardableResult
    func beginRun(
        version: String,
        build: String
    ) -> PreviousRun {
        guard !isSuppressed else { return PreviousRun(endedUnexpectedly: false) }
        let previous = PreviousRun(
            endedUnexpectedly: defaults.bool(forKey: Key.foregroundRunActive),
            version: defaults.string(forKey: Key.lastRunVersion),
            build: defaults.string(forKey: Key.lastRunBuild),
            lastHeartbeat: defaults.object(forKey: Key.lastHeartbeat) as? Date,
            sessionID: defaults.string(forKey: Key.lastSessionID)
                .flatMap(UUID.init(uuidString:)),
            turnID: defaults.string(forKey: Key.lastTurnID)
                .flatMap(UUID.init(uuidString:)),
            activity: defaults.string(forKey: Key.lastActivity),
            wasUnderDebugger: defaults.bool(forKey: Key.lastRunUnderDebugger)
        )
        previousRun = previous
        defaults.set(version, forKey: Key.lastRunVersion)
        defaults.set(build, forKey: Key.lastRunBuild)
        defaults.set(Self.isDebuggerAttached, forKey: Key.lastRunUnderDebugger)
        defaults.set(false, forKey: Key.foregroundRunActive)
        return previous
    }

    func markForegroundActive() {
        guard !isSuppressed else { return }
        defaults.set(true, forKey: Key.foregroundRunActive)
        defaults.set(Date(), forKey: Key.lastHeartbeat)
    }

    func markForegroundEnded() {
        guard !isSuppressed else { return }
        defaults.set(false, forKey: Key.foregroundRunActive)
        defaults.set(Date(), forKey: Key.lastHeartbeat)
    }

    /// 记录当前正在处理的上下文，崩溃报告用它定位 session。
    func recordActivity(
        sessionID: UUID?,
        turnID: UUID?,
        activity: String
    ) {
        guard !isSuppressed else { return }
        if let sessionID {
            defaults.set(sessionID.uuidString, forKey: Key.lastSessionID)
        }
        if let turnID {
            defaults.set(turnID.uuidString, forKey: Key.lastTurnID)
        } else {
            defaults.removeObject(forKey: Key.lastTurnID)
        }
        defaults.set(activity, forKey: Key.lastActivity)
        defaults.set(Date(), forKey: Key.lastHeartbeat)
    }

    /// 上报完成后清掉上一次运行的痕迹，避免重复上报同一次崩溃。
    func clearPreviousRunMarkers() {
        previousRun = nil
        defaults.removeObject(forKey: Key.lastActivity)
    }
}

/// BUG 0032：崩溃报告必须携带系统 MetricKit 的 MXCrashDiagnostic 证据。
enum CrashReportEligibility {
    static func isSystemConfirmed(source: String) -> Bool {
        source == DiagnosticReportEvidenceSource.metricKit.rawValue
    }

    static func isSystemConfirmed(report: DiagnosticReport) -> Bool {
        report.evidenceSource == .metricKit
    }
}

enum AppBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "unknown"
    }
}
