import ActivityKit
import Foundation
import UserNotifications

enum WorkoutLiveActivityProgress {
    static func fraction(from snapshot: GuidedWorkoutScreenSnapshot) -> Double {
        let segments = snapshot.progressExercises.flatMap(\.sets)
        guard !segments.isEmpty else { return 0 }
        let total = segments.map(\.completionFraction).reduce(0, +)
        return min(max(total / Double(segments.count), 0), 1)
    }
}

@MainActor
final class WorkoutSystemProjectionCoordinator {
    static let shared = WorkoutSystemProjectionCoordinator()
    private let updates = WorkoutProjectionSerialQueue()
    private var cachedActivities: [UUID: Activity<SomaWorkoutActivityAttributes>] = [:]
    private var updateSequences: [UUID: Int] = [:]

    private init() {}

    func update(
        session: WorkoutSession,
        completedSetCount: Int,
        totalSetCount: Int,
        progressFraction: Double = 0
    ) async {
        await update(
            sessionID: session.id,
            status: session.status,
            guidedPhase: session.guidedPhase,
            restTargetEndAt: session.restTargetEndAt,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount,
            progressFraction: progressFraction
        )
    }

    func update(
        sessionID: UUID,
        status: WorkoutSessionStatus,
        guidedPhase: GuidedWorkoutPhase,
        restTargetEndAt: Date?,
        completedSetCount: Int,
        totalSetCount: Int,
        progressFraction: Double = 0
    ) async {
        await updates.enqueue(sessionID: sessionID) { [self] in
            await applyUpdate(
                sessionID: sessionID, status: status, guidedPhase: guidedPhase,
                restTargetEndAt: restTargetEndAt,
                completedSetCount: completedSetCount, totalSetCount: totalSetCount,
                progressFraction: progressFraction
            )
        }.value
    }

    private func applyUpdate(
        sessionID: UUID,
        status: WorkoutSessionStatus,
        guidedPhase: GuidedWorkoutPhase,
        restTargetEndAt: Date?,
        completedSetCount: Int,
        totalSetCount: Int,
        progressFraction: Double
    ) async {
        let sequence = nextSequence(for: sessionID)
        let state = Self.contentState(
            status: status,
            guidedPhase: guidedPhase,
            restTargetEndAt: restTargetEndAt,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount,
            progressFraction: progressFraction,
            updateSequence: sequence
        )
        let content = ActivityContent(
            state: state,
            staleDate: state.restEndAt?.addingTimeInterval(60)
                ?? Date().addingTimeInterval(8 * 60 * 60),
            relevanceScore: status == .paused ? 20 : 80
        )

        if let activity = resolvedActivity(for: sessionID) {
            if status == .completed || status == .abandoned {
                await activity.end(
                    content,
                    dismissalPolicy: .after(.now.addingTimeInterval(60))
                )
                cachedActivities[sessionID] = nil
            } else {
                await activity.update(content)
            }
        } else if status == .active || status == .paused,
                  ActivityAuthorizationInfo().areActivitiesEnabled
        {
            do {
                let activity = try Activity.request(
                    attributes: SomaWorkoutActivityAttributes(sessionID: sessionID),
                    content: content,
                    pushType: nil
                )
                cachedActivities[sessionID] = activity
            } catch {
                if let activity = resolvedActivity(for: sessionID) {
                    await activity.update(content)
                }
            }
        }

        await updateRestNotification(
            sessionID: sessionID,
            restEndAt: state.restEndAt
        )
    }

    private func nextSequence(for sessionID: UUID) -> Int {
        let next = (updateSequences[sessionID] ?? 0) + 1
        updateSequences[sessionID] = next
        return next
    }

    private func resolvedActivity(
        for sessionID: UUID
    ) -> Activity<SomaWorkoutActivityAttributes>? {
        let live = Activity<SomaWorkoutActivityAttributes>.activities.filter {
            $0.attributes.sessionID == sessionID
        }
        if let preferred = live.first(where: { $0.activityState == .active })
            ?? live.first(where: { $0.activityState != .dismissed })
        {
            cachedActivities[sessionID] = preferred
            return preferred
        }
        if let cached = cachedActivities[sessionID],
           cached.activityState != .dismissed
        {
            return cached
        }
        return nil
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
        cachedActivities[sessionID] = nil
        updateSequences[sessionID] = nil
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
        totalSetCount: Int,
        progressFraction: Double = 0,
        updateSequence: Int = 0
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
                : nil,
            progressFraction: progressFraction,
            updateSequence: updateSequence
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
        guard !Task.isCancelled, restEndAt > .now,
              refreshed.authorizationStatus == .authorized
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
