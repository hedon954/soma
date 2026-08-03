import ActivityKit
import Foundation
import UserNotifications

@MainActor
final class WorkoutSystemProjectionCoordinator {
    static let shared = WorkoutSystemProjectionCoordinator()

    private init() {}

    func update(
        session: WorkoutSession,
        completedSetCount: Int,
        totalSetCount: Int
    ) async {
        let state = contentState(
            session: session,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount
        )
        let content = ActivityContent(
            state: state,
            staleDate: session.restTargetEndAt?.addingTimeInterval(60)
        )

        if let activity = Activity<SomaWorkoutActivityAttributes>.activities
            .first(where: { $0.attributes.sessionID == session.id })
        {
            if session.status == .completed || session.status == .abandoned {
                await activity.end(
                    content,
                    dismissalPolicy: .after(.now.addingTimeInterval(60))
                )
            } else {
                await activity.update(content)
            }
        } else if session.status == .active || session.status == .paused,
                  ActivityAuthorizationInfo().areActivitiesEnabled
        {
            _ = try? Activity.request(
                attributes: SomaWorkoutActivityAttributes(sessionID: session.id),
                content: content,
                pushType: nil
            )
        }

        await updateRestNotification(for: session)
    }

    func end(
        session: WorkoutSession,
        completedSetCount: Int,
        totalSetCount: Int
    ) async {
        let state = SomaWorkoutActivityAttributes.ContentState(
            phaseRaw: "completed",
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount,
            restEndAt: nil
        )
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<SomaWorkoutActivityAttributes>.activities
            where activity.attributes.sessionID == session.id
        {
            await activity.end(
                content,
                dismissalPolicy: .after(.now.addingTimeInterval(60))
            )
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID(for: session.id)]
        )
    }

    private func contentState(
        session: WorkoutSession,
        completedSetCount: Int,
        totalSetCount: Int
    ) -> SomaWorkoutActivityAttributes.ContentState {
        let phase: String = if session.status == .paused {
            "paused"
        } else if session.status == .completed || session.status == .abandoned {
            "completed"
        } else {
            session.guidedPhase == .resting ? "resting" : "active"
        }
        return SomaWorkoutActivityAttributes.ContentState(
            phaseRaw: phase,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount,
            restEndAt: session.guidedPhase == .resting
                ? session.restTargetEndAt
                : nil
        )
    }

    private func updateRestNotification(for session: WorkoutSession) async {
        let center = UNUserNotificationCenter.current()
        let identifier = notificationID(for: session.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard session.guidedPhase == .resting,
              let restEndAt = session.restTargetEndAt,
              restEndAt > .now
        else {
            return
        }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let refreshed = await center.notificationSettings()
        guard refreshed.authorizationStatus == .authorized
            || refreshed.authorizationStatus == .provisional
        else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "返回 Soma 开始下一组。"
        content.sound = .default
        content.userInfo = ["workout_session_id": session.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(restEndAt.timeIntervalSinceNow, 1),
            repeats: false
        )
        try? await center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        ))
    }

    private func notificationID(for sessionID: UUID) -> String {
        "workout-rest-\(sessionID.uuidString)"
    }
}
