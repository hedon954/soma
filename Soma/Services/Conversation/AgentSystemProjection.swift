import ActivityKit
import Foundation
import Observation
import UIKit
import UserNotifications

enum AgentSystemPreference {
    static let liveActivitiesKey = "agent.system.liveActivities"
    static let completionNotificationsKey = "agent.system.notifications"
}

@MainActor
@Observable
final class AgentSystemProjectionCoordinator {
    private(set) var lastErrorMessage: String?
    private(set) var activityPushTokens: [UUID: String] = [:]
    private var pushTokenTasks: [UUID: Task<Void, Never>] = [:]

    func project(
        jobs: [AgentJob],
        events: [PersistentAgentEvent],
        defaults: UserDefaults = .standard
    ) async {
        await project(
            jobs: jobs,
            operationCounts: Dictionary(
                grouping: events.filter { $0.kind == .span },
                by: \.jobID
            ).mapValues(\.count),
            defaults: defaults
        )
    }

    func project(
        jobs: [AgentJob],
        operationCounts: [UUID: Int],
        defaults: UserDefaults = .standard
    ) async {
        let liveEnabled = defaults.bool(
            forKey: AgentSystemPreference.liveActivitiesKey
        )
        let notificationEnabled = defaults.bool(
            forKey: AgentSystemPreference.completionNotificationsKey
        )
        let currentJob = jobs
            .filter { !$0.state.isTerminal && shouldDisplay($0) }
            .sorted { $0.createdAt < $1.createdAt }
            .first

        for job in jobs {
            let operationCount = operationCounts[job.id, default: 0]
            let queuedCount = jobs.count {
                !$0.state.isTerminal && $0.id != job.id
            }
            if liveEnabled, currentJob?.id == job.id {
                await updateActivity(
                    for: job,
                    operationCount: operationCount,
                    queuedCount: queuedCount
                )
            } else if job.state.isTerminal
                || Activity<SomaAgentJobAttributes>.activities.contains(
                    where: { $0.attributes.jobID == job.id }
                )
            {
                await endActivity(
                    for: job,
                    operationCount: operationCount,
                    queuedCount: queuedCount
                )
            }
            job.liveActivityProjectionCursor = max(
                job.liveActivityProjectionCursor,
                job.lastEventSequence
            )

            if notificationEnabled,
               job.state.isTerminal,
               job.notificationProjectionCursor < job.lastEventSequence
            {
                let activityExists = Activity<SomaAgentJobAttributes>
                    .activities.contains {
                        $0.attributes.jobID == job.id
                    }
                if !activityExists {
                    await notifyCompletion(for: job)
                }
                job.notificationProjectionCursor = job.lastEventSequence
            }
        }
    }

    func requestNotificationAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            lastErrorMessage = AppErrorMessage.message(for: error, operation: .general)
            return false
        }
    }

    private func updateActivity(
        for job: AgentJob,
        operationCount: Int,
        queuedCount: Int
    ) async {
        let state = contentState(
            for: job,
            operationCount: operationCount,
            queuedCount: queuedCount
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(15 * 60)
        )
        if let activity = Activity<SomaAgentJobAttributes>.activities.first(
            where: { $0.attributes.jobID == job.id }
        ) {
            guard activity.content.state.sequence <= state.sequence else {
                return
            }
            await activity.update(content)
            publishPushToken(activity.pushToken, jobID: job.id)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let activity = try Activity.request(
                attributes: SomaAgentJobAttributes(
                    jobID: job.id,
                    turnID: job.turnID
                ),
                content: content,
                pushType: job.backend == .remote ? .token : nil
            )
            observePushToken(for: activity, jobID: job.id)
        } catch {
            lastErrorMessage = AppErrorMessage.message(for: error, operation: .general)
        }
    }

    private func endActivity(
        for job: AgentJob,
        operationCount: Int,
        queuedCount: Int
    ) async {
        let content = ActivityContent(
            state: contentState(
                for: job,
                operationCount: operationCount,
                queuedCount: queuedCount
            ),
            staleDate: nil
        )
        for activity in Activity<SomaAgentJobAttributes>.activities
            where activity.attributes.jobID == job.id
        {
            guard activity.content.state.sequence <= job.lastEventSequence else {
                continue
            }
            await activity.end(
                content,
                dismissalPolicy: job.state.isTerminal
                    ? .after(.now.addingTimeInterval(60))
                    : .immediate
            )
        }
        pushTokenTasks[job.id]?.cancel()
        pushTokenTasks[job.id] = nil
        activityPushTokens[job.id] = nil
    }

    private func contentState(
        for job: AgentJob,
        operationCount: Int,
        queuedCount: Int
    ) -> SomaAgentJobAttributes.ContentState {
        SomaAgentJobAttributes.ContentState(
            phaseRaw: job.state.rawValue,
            operationCount: operationCount,
            queuedCount: queuedCount,
            sequence: job.lastEventSequence,
            isStale: false
        )
    }

    private func notifyCompletion(for job: AgentJob) async {
        let content = UNMutableNotificationContent()
        switch job.state {
        case .succeeded:
            content.title = "Soma 任务已完成"
            content.body = "打开 Soma 查看结果。"
        case .failed:
            content.title = "Soma 任务未完成"
            content.body = "打开 Soma 查看原因并重试。"
        case .cancelled:
            content.title = "Soma 任务已取消"
            content.body = "已保留发送内容和执行记录。"
        default:
            return
        }
        content.sound = .default
        content.userInfo = [
            "turn_id": job.turnID.uuidString
        ]
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: "agent-job-\(job.id.uuidString)",
                    content: content,
                    trigger: nil
                )
            )
        } catch {
            lastErrorMessage = AppErrorMessage.message(for: error, operation: .general)
        }
    }

    private func observePushToken(
        for activity: Activity<SomaAgentJobAttributes>,
        jobID: UUID
    ) {
        pushTokenTasks[jobID]?.cancel()
        pushTokenTasks[jobID] = Task {
            for await token in activity.pushTokenUpdates {
                cachePushToken(Self.hex(token), jobID: jobID)
            }
        }
    }

    private func publishPushToken(_ token: Data?, jobID: UUID) {
        guard let token else { return }
        cachePushToken(Self.hex(token), jobID: jobID)
    }

    func cachePushToken(_ token: String, jobID: UUID) {
        guard !token.isEmpty else { return }
        activityPushTokens[jobID] = token
        NotificationCenter.default.post(
            name: .agentActivityPushTokenUpdated,
            object: nil,
            userInfo: [
                "job_id": jobID,
                "token": token
            ]
        )
    }

    private static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private func shouldDisplay(_ job: AgentJob) -> Bool {
        job.backend == .remote || !job.mediaAttachments.isEmpty
    }
}

extension Notification.Name {
    static let agentActivityPushTokenUpdated = Notification.Name(
        "agentActivityPushTokenUpdated"
    )
}

final class SomaAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor _: UIWindow?
    ) -> UIInterfaceOrientationMask {
        WorkoutInterfaceOrientationPolicy.shared.supportedOrientations
    }

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRemoteUploadCoordinator.shared.activate()
        // 单测宿主是 App 本身，测试结束会被直接杀进程；哨兵在测试里不置位也不上报。
        guard !AppRunSentinel.isRunningUnderTests else { return true }
        MainActor.assumeIsolated {
            let previousRun = AppRunSentinel.shared.beginRun(
                version: AppBuildInfo.version,
                build: AppBuildInfo.build
            )
            AppLifecycleDiagnostics.launched(
                version: AppBuildInfo.version,
                build: AppBuildInfo.build,
                previousRunEndedCleanly: !previousRun.endedUnexpectedly
            )
            CrashDiagnosticsCoordinator.shared.activate(
                previousRun: previousRun
            )
        }
        return true
    }

    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier ==
            BackgroundRemoteUploadCoordinator.sessionIdentifier
        else {
            completionHandler()
            return
        }
        BackgroundRemoteUploadCoordinator.shared.handleBackgroundEvents(
            completion: completionHandler
        )
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let rawID = userInfo["turn_id"] as? String,
           let turnID = UUID(uuidString: rawID)
        {
            SomaCaptureRouter.shared.requestAgentTurn(turnID)
        } else if let rawID = userInfo["workout_session_id"] as? String,
                  let sessionID = UUID(uuidString: rawID)
        {
            SomaCaptureRouter.shared.requestWorkoutSession(sessionID)
        }
    }
}
