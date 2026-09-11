import ActivityKit
import Foundation
import UserNotifications

@MainActor
final class WorkoutSystemProjectionCoordinator {
    static let shared = WorkoutSystemProjectionCoordinator()
    private let updates = WorkoutProjectionSerialQueue()

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
        await updates.enqueue(sessionID: sessionID) { [self] in
            await applyUpdate(
                sessionID: sessionID, status: status, guidedPhase: guidedPhase,
                restTargetEndAt: restTargetEndAt,
                completedSetCount: completedSetCount, totalSetCount: totalSetCount
            )
        }.value
    }

    private func applyUpdate(
        sessionID: UUID,
        status: WorkoutSessionStatus,
        guidedPhase: GuidedWorkoutPhase,
        restTargetEndAt: Date?,
        completedSetCount: Int,
        totalSetCount: Int
    ) async {
        let state = Self.contentState(
            status: status,
            guidedPhase: guidedPhase,
            restTargetEndAt: restTargetEndAt,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount
        )
        let content = ActivityContent(
            state: state,
            staleDate: state.restEndAt?.addingTimeInterval(60)
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
            restEndAt: state.restEndAt
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
        await updates.enqueue(sessionID: sessionID) { [self] in
            await applyEnd(
                sessionID: sessionID, completedSetCount: completedSetCount, totalSetCount: totalSetCount
            )
        }.value
    }

    private func applyEnd(sessionID: UUID, completedSetCount: Int, totalSetCount: Int) async {
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

    static func contentState(
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
            restEndAt: status == .active && guidedPhase == .resting
                ? restTargetEndAt
                : nil
        )
    }

    private func updateRestNotification(
        sessionID: UUID,
        restEndAt: Date?
    ) async {
        let center = UNUserNotificationCenter.current()
        let identifier = notificationID(for: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard !Task.isCancelled, let restEndAt,
              restEndAt > .now
        else {
            return
        }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let refreshed = await center.notificationSettings()
        guard !Task.isCancelled, restEndAt > .now else { return }
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

/// Serialize system writes even when cancellation cannot stop an in-flight system call.
/// The newest update removes/replaces the previous notification only after it finishes.
@MainActor
final class WorkoutProjectionSerialQueue {
    private var pending: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    func enqueue(sessionID: UUID, operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = pending[sessionID]?.task
        previous?.cancel()
        let token = UUID()
        let task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
            if self?.pending[sessionID]?.token == token {
                self?.pending[sessionID] = nil
            }
        }
        pending[sessionID] = (token, task)
        return task
    }
}
