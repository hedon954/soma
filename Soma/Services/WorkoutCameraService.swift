@preconcurrency import AVFoundation
import Observation
import SwiftUI
import UIKit

enum WorkoutCameraState: Equatable {
    case idle
    case requestingPermission
    case previewing
    case recording
    case unavailable(String)

    var message: String {
        switch self {
        case .idle:
            "相机尚未启动"
        case .requestingPermission:
            "正在请求相机权限"
        case .previewing:
            "请确认全身位于取景框内"
        case .recording:
            "正在录制本动作目标组"
        case let .unavailable(message):
            message
        }
    }
}

enum WorkoutCameraError: LocalizedError {
    case permissionDenied
    case frontCameraUnavailable
    case configurationFailed
    case insufficientStorage
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "没有相机权限；训练仍可继续，可在系统设置中开启。"
        case .frontCameraUnavailable:
            "当前设备没有可用的前置摄像头。"
        case .configurationFailed:
            "相机启动失败；训练仍可继续。"
        case .insufficientStorage:
            "可用存储空间不足，已跳过本次录像。"
        case let .recordingFailed(message):
            "录像失败：\(message)"
        }
    }
}

@MainActor
@Observable
final class WorkoutCameraService: NSObject, WorkoutRecordingControlling {
    private(set) var state: WorkoutCameraState = .idle
    private(set) var lastSavedPath: String?

    @ObservationIgnored nonisolated(unsafe) let captureSession = AVCaptureSession()
    @ObservationIgnored private nonisolated(unsafe) let movieOutput =
        AVCaptureMovieFileOutput()
    @ObservationIgnored private let recordingDelegate = MovieRecordingDelegate()
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "top.hedon.soma.workout-camera"
    )
    @ObservationIgnored private nonisolated(unsafe) var isConfigured = false
    @ObservationIgnored private var temporaryURL: URL?
    @ObservationIgnored private var stopContinuation:
        CheckedContinuation<String?, Error>?
    @ObservationIgnored private var discardCurrentRecording = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        recordingDelegate.completion = { [weak self] url, error in
            Task { @MainActor in
                self?.finishRecording(at: url, error: error)
            }
        }
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func prepare() async throws {
        state = .requestingPermission
        guard await cameraPermissionGranted() else {
            state = .unavailable(WorkoutCameraError.permissionDenied.localizedDescription)
            throw WorkoutCameraError.permissionDenied
        }
        do {
            try await configureIfNeeded()
            await startSession()
            state = .previewing
        } catch {
            state = .unavailable(error.localizedDescription)
            throw error
        }
    }

    func startRecording(performanceID: UUID) async throws {
        guard case .previewing = state else {
            throw WorkoutCameraError.configurationFailed
        }
        guard hasRecordingCapacity else {
            state = .unavailable(
                WorkoutCameraError.insufficientStorage.localizedDescription
            )
            throw WorkoutCameraError.insufficientStorage
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "soma-set-\(performanceID.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        temporaryURL = url
        discardCurrentRecording = false
        movieOutput.startRecording(
            to: url,
            recordingDelegate: recordingDelegate
        )
        state = .recording
    }

    func stopRecording() async throws -> String? {
        guard movieOutput.isRecording else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            movieOutput.stopRecording()
        }
    }

    func cancelRecording() async {
        discardCurrentRecording = true
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }

    func stopPreview() async {
        await cancelRecording()
        await withCheckedContinuation { continuation in
            sessionQueue.async { [captureSession] in
                if captureSession.isRunning {
                    captureSession.stopRunning()
                }
                continuation.resume()
            }
        }
        if case .unavailable = state {
            return
        }
        state = .idle
    }

    private func finishRecording(at url: URL, error: Error?) {
        defer {
            temporaryURL = nil
            discardCurrentRecording = false
            state = Self.settledState(
                after: state,
                sessionIsRunning: captureSession.isRunning
            )
        }
        if discardCurrentRecording {
            try? FileManager.default.removeItem(at: url)
            stopContinuation?.resume(returning: nil)
            stopContinuation = nil
            return
        }
        if let error {
            try? FileManager.default.removeItem(at: url)
            let resolved = WorkoutCameraError.recordingFailed(
                error.localizedDescription
            )
            stopContinuation?.resume(throwing: resolved)
            stopContinuation = nil
            state = .unavailable(resolved.localizedDescription)
            return
        }
        do {
            let path = try MediaStore.saveVideo(from: url)
            try? FileManager.default.removeItem(at: url)
            lastSavedPath = path
            stopContinuation?.resume(returning: path)
        } catch {
            try? FileManager.default.removeItem(at: url)
            stopContinuation?.resume(throwing: error)
            state = .unavailable(error.localizedDescription)
        }
        stopContinuation = nil
    }

    static func settledState(
        after current: WorkoutCameraState,
        sessionIsRunning: Bool
    ) -> WorkoutCameraState {
        if case .unavailable = current {
            return current
        }
        return sessionIsRunning ? .previewing : .idle
    }

    private func cameraPermissionGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureIfNeeded() async throws {
        guard !isConfigured else { return }
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        throwing: WorkoutCameraError.configurationFailed
                    )
                    return
                }
                do {
                    captureSession.beginConfiguration()
                    defer { captureSession.commitConfiguration() }
                    captureSession.sessionPreset = .high
                    guard let camera = AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: .front
                    ) else {
                        throw WorkoutCameraError.frontCameraUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard captureSession.canAddInput(input),
                          captureSession.canAddOutput(movieOutput)
                    else {
                        throw WorkoutCameraError.configurationFailed
                    }
                    captureSession.addInput(input)
                    captureSession.addOutput(movieOutput)
                    if let connection = movieOutput.connection(with: .video),
                       connection.isVideoMirroringSupported
                    {
                        connection.isVideoMirrored = true
                    }
                    isConfigured = true
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [captureSession] in
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
                continuation.resume()
            }
        }
    }

    private var hasRecordingCapacity: Bool {
        let values = try? FileManager.default
            .temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0)
            > 100 * 1024 * 1024
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.interrupt(
                    message: "App 进入后台，录像已停止；训练进度已保留。"
                )
            }
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.interrupt(
                    message: "相机被系统中断；训练进度不受影响。"
                )
            }
        })
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard ProcessInfo.processInfo.thermalState == .serious
                    || ProcessInfo.processInfo.thermalState == .critical
                else {
                    return
                }
                await self?.interrupt(
                    message: "设备温度较高，已停止录像；训练仍可继续。"
                )
            }
        })
    }

    private func interrupt(message: String) async {
        await cancelRecording()
        state = .unavailable(message)
    }
}

private final class MovieRecordingDelegate:
    NSObject,
    AVCaptureFileOutputRecordingDelegate
{
    var completion: ((URL, Error?) -> Void)?

    func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        completion?(outputFileURL, error)
    }
}

struct WorkoutCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context _: Context) {
        uiView.previewLayer?.session = session
    }
}

final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
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
