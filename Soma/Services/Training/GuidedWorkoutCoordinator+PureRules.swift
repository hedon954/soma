import AVFoundation
import Foundation

extension GuidedWorkoutCoordinator {
    static func terminalSetStatus(
        for effortStatuses: [WorkoutEffortStatus]
    ) -> WorkoutSetStatus? {
        guard !effortStatuses.isEmpty,
              effortStatuses.allSatisfy({
                  $0 == .completed || $0 == .skipped || $0 == .failed
              })
        else { return nil }
        if effortStatuses.allSatisfy({ $0 == .completed }) {
            return .completed
        }
        if effortStatuses.contains(.completed) {
            return .partial
        }
        if effortStatuses.contains(.failed) {
            return .failed
        }
        return .skipped
    }

    static func friendlyRecordingError(_ error: Error) -> String {
        AppErrorMessage.message(for: error, operation: .recording)
    }
}
