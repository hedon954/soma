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
        await update(
            sessionID: session.id,
            status: session.status,
            guidedPhase: session.guidedPhase,
            restTargetEndAt: session.restTargetEndAt,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount
        )
    }

    func update(
        sessionID: UUID,
        status: WorkoutSessionStatus,
        guidedPhase: GuidedWorkoutPhase,
        restTargetEndAt: Date?,
        completedSetCount: Int,
        totalSetCount: Int
    ) async {
        let state = contentState(
            status: status,
            guidedPhase: guidedPhase,
            restTargetEndAt: restTargetEndAt,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount
        )
        let content = ActivityContent(
            state: state,
            staleDate: restTargetEndAt?.addingTimeInterval(60)
        )

        if let activity = Activity<SomaWorkoutActivityAttributes>.activities
            .first(where: { $0.attributes.sessionID == sessionID })
        {
            if status == .completed || status == .abandoned {
                await activity.end(
                    content,
                    dismissalPolicy: .after(.now.addingTimeInterval(60))
                )
            } else {
                await activity.update(content)
            }
        } else if status == .active || status == .paused,
                  ActivityAuthorizationInfo().areActivitiesEnabled
        {
            _ = try? Activity.request(
                attributes: SomaWorkoutActivityAttributes(sessionID: sessionID),
                content: content,
                pushType: nil
            )
        }

        await updateRestNotification(
            sessionID: sessionID,
            guidedPhase: guidedPhase,
            restEndAt: restTargetEndAt
        )
    }

    func end(
        session: WorkoutSession,
        completedSetCount: Int,
        totalSetCount: Int
    ) async {
        await end(
            sessionID: session.id,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount
        )
    }

    func end(
        sessionID: UUID,
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
            where activity.attributes.sessionID == sessionID
        {
            await activity.end(
                content,
                dismissalPolicy: .after(.now.addingTimeInterval(60))
            )
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID(for: sessionID)]
        )
    }

    private func contentState(
        status: WorkoutSessionStatus,
        guidedPhase: GuidedWorkoutPhase,
        restTargetEndAt: Date?,
        completedSetCount: Int,
        totalSetCount: Int
    ) -> SomaWorkoutActivityAttributes.ContentState {
        let phase: String = if status == .paused {
            "paused"
        } else if status == .completed || status == .abandoned {
            "completed"
        } else {
            guidedPhase == .resting ? "resting" : "active"
        }
        return SomaWorkoutActivityAttributes.ContentState(
            phaseRaw: phase,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount,
            restEndAt: guidedPhase == .resting
                ? restTargetEndAt
                : nil
        )
    }

    private func updateRestNotification(
        sessionID: UUID,
        guidedPhase: GuidedWorkoutPhase,
        restEndAt: Date?
    ) async {
        let center = UNUserNotificationCenter.current()
        let identifier = notificationID(for: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard guidedPhase == .resting,
              let restEndAt,
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
        content.userInfo = ["workout_session_id": sessionID.uuidString]
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
