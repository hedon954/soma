@preconcurrency import AVFoundation
import Observation
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

enum WorkoutCaptureOrientation: String, Equatable, Sendable {
    case portrait
    case landscapeLeft
    case landscapeRight

    var aspectRatio: CGFloat {
        switch self {
        case .portrait:
            9 / 16
        case .landscapeLeft, .landscapeRight:
            16 / 9
        }
    }
}

struct WorkoutCaptureGeometry: Equatable, Sendable {
    var orientation: WorkoutCaptureOrientation
    var previewRotationAngle: Double
    var captureRotationAngle: Double
    var isMirrored: Bool

    static let portrait = WorkoutCaptureGeometry(
        orientation: .portrait,
        previewRotationAngle: 90,
        captureRotationAngle: 90,
        isMirrored: true
    )
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
    private(set) var captureGeometry = WorkoutCaptureGeometry.portrait
    private(set) var isCaptureGeometryLocked = false
    private(set) var isPreviewReady = false
    private(set) var previewIssueMessage: String?
    @ObservationIgnored let sharedPreviewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    @ObservationIgnored nonisolated(unsafe) let captureSession = AVCaptureSession()
    @ObservationIgnored private nonisolated(unsafe) let movieOutput =
        AVCaptureMovieFileOutput()
    @ObservationIgnored private nonisolated(unsafe) var captureDevice:
        AVCaptureDevice?
    @ObservationIgnored private var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var previewRotationObservation:
        NSKeyValueObservation?
    @ObservationIgnored private var captureRotationObservation:
        NSKeyValueObservation?
    @ObservationIgnored private var previewReadinessObservation:
        NSKeyValueObservation?
    @ObservationIgnored private let recordingDelegate = MovieRecordingDelegate()
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "top.hedon.soma.workout-camera"
    )
    @ObservationIgnored private nonisolated(unsafe) var isConfigured = false
    @ObservationIgnored private var temporaryURL: URL?
    @ObservationIgnored private var stopContinuation:
        CheckedContinuation<String?, Error>?
    @ObservationIgnored private var startContinuation:
        CheckedContinuation<Void, Error>?
    @ObservationIgnored private var discardCurrentRecording = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var preparationTask: Task<Void, Error>?
    @ObservationIgnored private var previewStartupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var activePreviewHostID: UUID?

    override init() {
        super.init()
        recordingDelegate.started = { [weak self] in
            Task { @MainActor in
                self?.recordingDidStart()
            }
        }
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
        if state == .previewing || state == .recording {
            return
        }
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await performPreparation()
        }
        preparationTask = task
        do {
            try await task.value
            preparationTask = nil
        } catch {
            preparationTask = nil
            throw error
        }
    }

    private func performPreparation() async throws {
        state = .requestingPermission
        guard await cameraPermissionGranted() else {
            state = .unavailable(WorkoutCameraError.permissionDenied.localizedDescription)
            throw WorkoutCameraError.permissionDenied
        }
        do {
            try await configureIfNeeded()
            try await startSession()
            sharedPreviewLayer.session = captureSession
            configureRotationCoordinatorIfPossible()
            state = .previewing
            refreshPreviewConnectionState()
            armPreviewStartupTimeout()
        } catch {
            state = .unavailable(error.localizedDescription)
            throw error
        }
    }

    func startRecording(performanceID: UUID, setID: UUID) async throws {
        if state == .recording {
            return
        }
        if state != .previewing {
            try await prepare()
        }
        guard hasRecordingCapacity else {
            state = .unavailable(
                WorkoutCameraError.insufficientStorage.localizedDescription
            )
            throw WorkoutCameraError.insufficientStorage
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "soma-set-\(performanceID.uuidString)-\(setID.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        temporaryURL = url
        discardCurrentRecording = false
        lockCaptureGeometry()
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            sessionQueue.async { [movieOutput, recordingDelegate] in
                movieOutput.startRecording(
                    to: url,
                    recordingDelegate: recordingDelegate
                )
            }
        }
    }

    func stopRecording() async throws -> String? {
        let isRecording = await withCheckedContinuation { continuation in
            sessionQueue.async { [movieOutput] in
                continuation.resume(returning: movieOutput.isRecording)
            }
        }
        guard isRecording else {
            unlockCaptureGeometry()
            return nil
        }
        let path = try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            sessionQueue.async { [movieOutput] in
                movieOutput.stopRecording()
            }
        }
        await stopCaptureSession()
        return path
    }

    func cancelRecording() async {
        discardCurrentRecording = true
        startContinuation?.resume(
            throwing: WorkoutCameraError.recordingFailed("录像已取消")
        )
        startContinuation = nil
        let isRecording = await withCheckedContinuation { continuation in
            sessionQueue.async { [movieOutput] in
                continuation.resume(returning: movieOutput.isRecording)
            }
        }
        if isRecording {
            _ = try? await withCheckedThrowingContinuation { continuation in
                stopContinuation = continuation
                sessionQueue.async { [movieOutput] in
                    movieOutput.stopRecording()
                }
            }
        } else {
            unlockCaptureGeometry()
        }
        await stopCaptureSession()
    }

    func attachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        hostID: UUID,
        videoGravity: AVLayerVideoGravity
    ) {
        guard layer === sharedPreviewLayer else { return }
        guard activePreviewHostID != hostID else {
            layer.videoGravity = videoGravity
            applyCaptureGeometry(captureGeometry)
            refreshPreviewConnectionState()
            return
        }

        activePreviewHostID = hostID
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        previewReadinessObservation = nil
        previewStartupTimeoutTask?.cancel()
        isPreviewReady = false
        previewIssueMessage = nil

        // Rebuild only the lightweight preview connection after a host handoff.
        // The capture session and movie output continue running unchanged.
        layer.session = nil
        layer.session = captureSession
        layer.videoGravity = videoGravity
        configureRotationCoordinatorIfPossible()
        applyCaptureGeometry(captureGeometry)
        observePreviewReadiness(on: layer, hostID: hostID)
        refreshPreviewConnectionState()
        armPreviewStartupTimeout()
    }

    func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        guard layer === sharedPreviewLayer else { return }
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
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
        previewStartupTimeoutTask?.cancel()
        previewStartupTimeoutTask = nil
        previewReadinessObservation = nil
        activePreviewHostID = nil
        isPreviewReady = false
        previewIssueMessage = nil
        state = .idle
    }

    #if DEBUG
        func useCaptureGeometryForTesting(_ geometry: WorkoutCaptureGeometry) {
            captureGeometry = geometry
            applyCaptureGeometry(geometry)
        }
    #endif

    private func finishRecording(at url: URL, error: Error?) {
        defer {
            temporaryURL = nil
            discardCurrentRecording = false
            state = Self.settledState(
                after: state,
                sessionIsRunning: captureSession.isRunning
            )
            unlockCaptureGeometry()
        }
        if discardCurrentRecording {
            try? FileManager.default.removeItem(at: url)
            startContinuation?.resume(
                throwing: WorkoutCameraError.recordingFailed("录像已取消")
            )
            startContinuation = nil
            stopContinuation?.resume(returning: nil)
            stopContinuation = nil
            return
        }
        if let error {
            try? FileManager.default.removeItem(at: url)
            let resolved = WorkoutCameraError.recordingFailed(
                error.localizedDescription
            )
            startContinuation?.resume(throwing: resolved)
            startContinuation = nil
            stopContinuation?.resume(throwing: resolved)
            stopContinuation = nil
            state = .unavailable(resolved.localizedDescription)
            return
        }
        if startContinuation != nil {
            try? FileManager.default.removeItem(at: url)
            let resolved = WorkoutCameraError.recordingFailed(
                "系统未确认录像已经开始"
            )
            startContinuation?.resume(throwing: resolved)
            startContinuation = nil
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

    private func recordingDidStart() {
        if discardCurrentRecording {
            sessionQueue.async { [movieOutput] in
                if movieOutput.isRecording {
                    movieOutput.stopRecording()
                }
            }
            return
        }
        state = .recording
        refreshPreviewConnectionState()
        armPreviewStartupTimeout()
        startContinuation?.resume()
        startContinuation = nil
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
                    captureDevice = camera
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

    private func startSession() async throws {
        let didStart = await withCheckedContinuation { continuation in
            sessionQueue.async { [captureSession] in
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
                continuation.resume(returning: captureSession.isRunning)
            }
        }
        guard didStart else {
            throw WorkoutCameraError.configurationFailed
        }
    }

    private func stopCaptureSession() async {
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
        previewStartupTimeoutTask?.cancel()
        isPreviewReady = false
        previewIssueMessage = nil
        state = .idle
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
            forName: .AVCaptureSessionRuntimeError,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.interrupt(
                    message: "相机运行异常，录像已停止；请退出本次取景后重试。"
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

    private func configureRotationCoordinatorIfPossible() {
        guard let captureDevice else {
            return
        }
        previewRotationObservation = nil
        captureRotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: captureDevice,
            previewLayer: sharedPreviewLayer
        )
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshCaptureGeometry()
            }
        }
        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshCaptureGeometry()
            }
        }
        refreshCaptureGeometry()
    }

    private func refreshPreviewConnectionState() {
        guard activePreviewHostID != nil else {
            isPreviewReady = false
            previewIssueMessage = nil
            return
        }

        isPreviewReady = sharedPreviewLayer.isPreviewing
        if isPreviewReady {
            previewIssueMessage = nil
            previewStartupTimeoutTask?.cancel()
            previewStartupTimeoutTask = nil
        }
    }

    private func observePreviewReadiness(
        on layer: AVCaptureVideoPreviewLayer,
        hostID: UUID
    ) {
        previewReadinessObservation = layer.observe(
            \.isPreviewing,
            options: [.initial, .new]
        ) { [weak self] layer, _ in
            Task { @MainActor [weak self] in
                guard let self, activePreviewHostID == hostID else { return }
                isPreviewReady = layer.isPreviewing
                if isPreviewReady {
                    previewIssueMessage = nil
                    previewStartupTimeoutTask?.cancel()
                    previewStartupTimeoutTask = nil
                }
            }
        }
    }

    private func armPreviewStartupTimeout() {
        guard let hostID = activePreviewHostID,
              state == .previewing || state == .recording,
              !isPreviewReady
        else {
            return
        }
        previewStartupTimeoutTask?.cancel()
        previewStartupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  !Task.isCancelled,
                  activePreviewHostID == hostID,
                  !sharedPreviewLayer.isPreviewing,
                  state == .previewing || state == .recording
            else {
                return
            }
            isPreviewReady = false
            previewIssueMessage = "相机画面未能显示；训练可以继续，请收起后重新进入取景。"
        }
    }

    private func refreshCaptureGeometry() {
        guard !isCaptureGeometryLocked,
              let rotationCoordinator
        else {
            return
        }
        let geometry = Self.captureGeometry(
            previewRotationAngle: Double(
                rotationCoordinator.videoRotationAngleForHorizonLevelPreview
            ),
            captureRotationAngle: Double(
                rotationCoordinator.videoRotationAngleForHorizonLevelCapture
            ),
            isMirrored: true
        )
        captureGeometry = geometry
        applyCaptureGeometry(geometry)
    }

    private func lockCaptureGeometry() {
        refreshCaptureGeometry()
        isCaptureGeometryLocked = true
        applyCaptureGeometry(captureGeometry)
    }

    private func unlockCaptureGeometry() {
        isCaptureGeometryLocked = false
        refreshCaptureGeometry()
    }

    private func applyCaptureGeometry(_ geometry: WorkoutCaptureGeometry) {
        if let connection = sharedPreviewLayer.connection {
            if connection.isVideoRotationAngleSupported(
                CGFloat(geometry.previewRotationAngle)
            ) {
                connection.videoRotationAngle = CGFloat(
                    geometry.previewRotationAngle
                )
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = geometry.isMirrored
            }
        }
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(
                CGFloat(geometry.captureRotationAngle)
            ) {
                connection.videoRotationAngle = CGFloat(
                    geometry.captureRotationAngle
                )
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = geometry.isMirrored
            }
        }
    }

    static func captureGeometry(
        previewRotationAngle: Double,
        captureRotationAngle: Double,
        isMirrored: Bool
    ) -> WorkoutCaptureGeometry {
        let normalized = normalizedAngle(captureRotationAngle)
        let orientation: WorkoutCaptureOrientation = switch normalized {
        case 0:
            .landscapeRight
        case 180:
            .landscapeLeft
        default:
            .portrait
        }
        return WorkoutCaptureGeometry(
            orientation: orientation,
            previewRotationAngle: normalizedAngle(previewRotationAngle),
            captureRotationAngle: normalized,
            isMirrored: isMirrored
        )
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        let normalized = value.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return (positive / 90).rounded() * 90
    }

    private func interrupt(message: String) async {
        await cancelRecording()
        state = .unavailable(message)
    }
}

private final class MovieRecordingDelegate:
    NSObject,
    @unchecked Sendable,
    AVCaptureFileOutputRecordingDelegate
{
    var started: (() -> Void)?
    var completion: ((URL, Error?) -> Void)?

    func fileOutput(
        _: AVCaptureFileOutput,
        didStartRecordingTo _: URL,
        from _: [AVCaptureConnection]
    ) {
        started?()
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
