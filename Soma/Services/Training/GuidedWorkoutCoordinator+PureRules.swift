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
        if let cameraError = error as? WorkoutCameraError {
            return cameraError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            return "相机会话中断，请重试本组录像。训练仍可继续。"
        }
        let description = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return "录像未能开始；训练仍可继续，可稍后重试。"
        }
        return description
    }
}
