import AVFoundation
import Foundation
import Observation

struct WorkoutPreviewHostWaiter {
    let previousHostID: UUID?
    let continuation: CheckedContinuation<Void, Never>
}

final class MovieRecordingDelegate:
    NSObject,
    @unchecked Sendable,
    AVCaptureFileOutputRecordingDelegate
{
    var started: ((URL) -> Void)?
    var completion: ((URL, Error?) -> Void)?

    func fileOutput(
        _: AVCaptureFileOutput,
        didStartRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection]
    ) {
        started?(outputFileURL)
    }

    func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        completion?(outputFileURL, error)
    }
}

@MainActor
@Observable
final class WorkoutRuntime {
    let camera: WorkoutCameraService
    let coordinator: GuidedWorkoutCoordinator

    init() {
        let camera = WorkoutCameraService()
        self.camera = camera
        coordinator = GuidedWorkoutCoordinator(
            recorder: camera,
            cues: SystemWorkoutCueProvider()
        )
    }
}

enum GuidedWorkoutError: LocalizedError, Equatable {
    case missingSession
    case missingPerformance
    case missingSet
    case missingEffort
    case noPendingEffortForRecording
    case sessionNotReadyForCompletion
    case missingWorkoutProjection

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "没有可继续的训练。"
        case .missingPerformance:
            "当前动作不存在。"
        case .missingSet:
            "当前训练组不存在。"
        case .missingEffort:
            "当前训练动作侧不存在。"
        case .noPendingEffortForRecording:
            "没有可预约录像的下一组；你仍可在动作开始后点击录像。"
        case .sessionNotReadyForCompletion:
            "训练尚未完成，暂时不能结束。"
        case .missingWorkoutProjection:
            "动作训练记录尚未保存，请重试。"
        }
    }
}

@MainActor
extension WorkoutCameraService {
    static func shouldHandleLifecycleInterruption(
        state: WorkoutCameraState,
        hasActiveAttempt: Bool,
        hasPreparation: Bool
    ) -> Bool {
        if hasActiveAttempt || hasPreparation {
            return true
        }
        switch state {
        case .requestingPermission,
             .configuring,
             .startingSession,
             .previewing,
             .startingRecording,
             .recording:
            return true
        case .idle, .unavailable:
            return false
        }
    }

    static func shouldRebuildCaptureResources(
        requiresRebuild: Bool,
        hasActiveAttempt: Bool
    ) -> Bool {
        requiresRebuild && !hasActiveAttempt
    }

    static func shouldRecoverAfterInterruptionEnded(
        isOwnedSession: Bool,
        shouldRecover: Bool
    ) -> Bool {
        isOwnedSession && shouldRecover
    }
}
