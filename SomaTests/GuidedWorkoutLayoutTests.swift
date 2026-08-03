import AVFoundation
@testable import Soma
import SwiftUI
import XCTest

final class GuidedWorkoutLayoutTests: XCTestCase {
    @MainActor
    func testPreviewUsesOneSharedCaptureExactLayerAcrossHosts() {
        let camera = WorkoutCameraService()
        let layer = camera.sharedPreviewLayer
        let compactHost = CameraPreviewView(frame: .zero)
        let expandedHost = CameraPreviewView(frame: .zero)

        compactHost.installPreviewLayer(layer)
        XCTAssertTrue(layer.superlayer === compactHost.layer)

        expandedHost.installPreviewLayer(layer)
        compactHost.removePreviewLayerIfOwned(layer)

        XCTAssertTrue(layer.superlayer === expandedHost.layer)
        XCTAssertEqual(layer.videoGravity, .resizeAspect)
    }

    @MainActor
    func testStalePreviewHostCannotStealLayerBackAfterExpansion() {
        let camera = WorkoutCameraService()
        let layer = camera.sharedPreviewLayer
        let compactHost = CameraPreviewView(frame: .zero)
        let expandedHost = CameraPreviewView(frame: .zero)

        compactHost.installPreviewLayer(layer)
        expandedHost.installPreviewLayer(layer)

        // SwiftUI may update the outgoing representable after the new branch is visible.
        compactHost.installPreviewLayer(layer)
        compactHost.removePreviewLayerIfOwned(layer)

        XCTAssertTrue(layer.superlayer === expandedHost.layer)
    }

    func testRecordingWithoutVisiblePreviewShowsActionableState() {
        XCTAssertEqual(
            WorkoutCameraSurfacePresentation.resolve(
                cameraState: .recording,
                isPreviewReady: false,
                previewIssueMessage: nil,
                recordingErrorMessage: nil
            ),
            .loading("正在连接相机画面…")
        )
        XCTAssertEqual(
            WorkoutCameraSurfacePresentation.resolve(
                cameraState: .recording,
                isPreviewReady: false,
                previewIssueMessage: "相机画面没有正常显示；请收起后重试。",
                recordingErrorMessage: nil
            ),
            .failed("相机画面没有正常显示；请收起后重试。")
        )
        XCTAssertEqual(
            WorkoutCameraSurfacePresentation.resolve(
                cameraState: .previewing,
                isPreviewReady: true,
                previewIssueMessage: nil,
                recordingErrorMessage: "录像启动失败；训练仍可继续。"
            ),
            .failed("录像启动失败；训练仍可继续。")
        )
    }

    @MainActor
    func testPreviewLayerBecomesReadyOnlyAfterEnteringWindow() {
        let view = CameraPreviewView(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer()
        var readyLayers: [AVCaptureVideoPreviewLayer] = []
        view.onPreviewLayerReady = { layer, _ in readyLayers.append(layer) }
        view.installPreviewLayer(layer)

        XCTAssertTrue(readyLayers.isEmpty)

        let controller = UIViewController()
        controller.view.addSubview(view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        view.frame = controller.view.bounds
        view.layoutIfNeeded()

        XCTAssertEqual(readyLayers.count, 1)
        XCTAssertTrue(readyLayers[0] === layer)
        window.isHidden = true
    }

    func testCameraLayoutFollowsInterfaceInsteadOfLockedCaptureGeometry() {
        XCTAssertEqual(
            WorkoutCaptureLayout.previewAspectRatio(isLandscape: false),
            9.0 / 16.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WorkoutCaptureLayout.previewAspectRatio(isLandscape: true),
            16.0 / 9.0,
            accuracy: 0.0001
        )

        let portraitPIP = WorkoutCaptureLayout.compactPreviewWidth(
            availableWidth: 390,
            isLandscape: false
        )
        let landscapeCameraShare = WorkoutCaptureLayout.landscapeCameraShare(
            availableWidth: 844
        )
        XCTAssertGreaterThanOrEqual(portraitPIP, 120)
        XCTAssertGreaterThanOrEqual(landscapeCameraShare, 0.68)
        XCTAssertEqual(
            WorkoutCaptureLayout.portraitCameraRegionHeight(
                availableHeight: 844,
                headerHeight: 44,
                controlsHeight: 260,
                spacing: 12
            ),
            516
        )
    }

    func testExpandedActionTitleCombinesExerciseAndTargetOnOneLine() {
        XCTAssertEqual(
            GuidedWorkoutDisplayText.expandedActionTitle(
                exerciseName: "引体向上",
                targetText: "自重 × 5 次"
            ),
            "引体向上（自重、5 次）"
        )
        XCTAssertEqual(
            GuidedWorkoutDisplayText.expandedActionTitle(
                exerciseName: "杠铃深蹲",
                targetText: "60 kg × 5 次"
            ),
            "杠铃深蹲（60 kg、5 次）"
        )
    }

    @MainActor
    func testGuidedWorkoutOrientationPolicyIncludesBothLandscapeDirections() {
        XCTAssertEqual(
            WorkoutInterfaceOrientationPolicy.supportedOrientations(
                isGuidedWorkoutActive: false
            ),
            .portrait
        )
        XCTAssertEqual(
            WorkoutInterfaceOrientationPolicy.supportedOrientations(
                isGuidedWorkoutActive: true
            ),
            [.portrait, .landscapeLeft, .landscapeRight]
        )
        XCTAssertEqual(
            WorkoutInterfaceOrientationPolicy.requestedOrientation(
                for: .portrait
            ),
            .portrait
        )
        XCTAssertEqual(
            WorkoutInterfaceOrientationPolicy.requestedOrientation(
                for: .landscapeLeft
            ),
            .landscapeRight
        )
        XCTAssertEqual(
            WorkoutInterfaceOrientationPolicy.requestedOrientation(
                for: .landscapeRight
            ),
            .landscapeLeft
        )
        XCTAssertNil(
            WorkoutInterfaceOrientationPolicy.requestedOrientation(
                for: .faceUp
            )
        )
    }

    @MainActor
    func testVisibleCountdownPublishesCompletionAtDeadline() async {
        let completed = expectation(description: "倒计时结束")
        let view = GuidedSetCountdownView(
            set: nil,
            targetText: "5 次",
            phaseStartedAt: .now.addingTimeInterval(-4),
            onTick: { _ in },
            onFinished: { completed.fulfill() }
        )
        .frame(width: 390, height: 844)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false

        await fulfillment(of: [completed], timeout: 1)
        window.isHidden = true
    }

    @MainActor
    func testExpandedCaptureLandscapeRendersAtPhoneAspectRatio() throws {
        let size = CGSize(width: 844, height: 390)
        let camera = WorkoutCameraService()
        camera.useCaptureGeometryForTesting(WorkoutCaptureGeometry(
            orientation: .landscapeRight,
            previewRotationAngle: 0,
            captureRotationAngle: 0,
            isMirrored: true
        ))
        let sessionID = UUID()
        let exerciseID = UUID()
        let prescription = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "引体向上",
            order: 1,
            targetSets: 5,
            targetReps: 5,
            targetWeightKG: 0,
            targetRestSeconds: 120,
            firstSetIsWarmup: true
        )
        let performance = ExercisePerformance(
            sessionID: sessionID,
            exerciseID: exerciseID,
            exerciseName: "引体向上",
            order: 1,
            prescriptionSnapshot: prescription,
            status: .active
        )
        let sets = (1 ... 5).map { order in
            WorkoutSet(
                performanceID: performance.id,
                order: order,
                kind: order == 1 ? .warmup : .working,
                plannedReps: 5,
                plannedWeightKG: 0,
                plannedRestSeconds: 120,
                actualReps: order == 1 ? 5 : nil,
                actualWeightKG: order == 1 ? 0 : nil,
                status: order == 1
                    ? .completed
                    : (order == 2 ? .inProgress : .pending)
            )
        }
        let view = GuidedExpandedCaptureView(
            camera: camera,
            sessionStartedAt: .now.addingTimeInterval(-38),
            performance: performance,
            performanceCount: 4,
            set: sets[1],
            sets: sets,
            targetText: "自重 × 5",
            coachingNote: "保持躯干稳定，在可控范围内完成本组。",
            isLandscape: true,
            cameraErrorMessage: nil,
            onCollapse: {},
            onPause: {},
            onComplete: {},
            onEdit: {},
            onMore: {}
        )
        .frame(width: size.width, height: size.height)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
        let data = try XCTUnwrap(image.pngData())
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "SomaGuidedLandscapeQA.png")
        try data.write(to: snapshotURL, options: .atomic)

        XCTAssertEqual(image.size.width, size.width)
        XCTAssertEqual(image.size.height, size.height)
        XCTAssertGreaterThan(data.count, 10000)
        window.isHidden = true
    }

    @MainActor
    func testExpandedCapturePortraitKeepsActionAndFailureVisible() throws {
        let size = CGSize(width: 390, height: 844)
        let camera = WorkoutCameraService()
        let sessionID = UUID()
        let exerciseID = UUID()
        let prescription = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "引体向上",
            order: 1,
            targetSets: 5,
            targetReps: 5,
            targetWeightKG: 0,
            targetRestSeconds: 120,
            firstSetIsWarmup: false
        )
        let performance = ExercisePerformance(
            sessionID: sessionID,
            exerciseID: exerciseID,
            exerciseName: "引体向上",
            order: 1,
            prescriptionSnapshot: prescription,
            status: .active
        )
        let sets = (1 ... 5).map { order in
            WorkoutSet(
                performanceID: performance.id,
                order: order,
                kind: .working,
                plannedReps: 5,
                plannedWeightKG: 0,
                plannedRestSeconds: 120,
                status: order == 1 ? .inProgress : .pending
            )
        }
        let view = GuidedExpandedCaptureView(
            camera: camera,
            sessionStartedAt: .now.addingTimeInterval(-10),
            performance: performance,
            performanceCount: 2,
            set: sets[0],
            sets: sets,
            targetText: "自重 × 5 次",
            coachingNote: "先让肩胛下沉，再把肘部拉向身体两侧。",
            isLandscape: false,
            cameraErrorMessage: "相机画面未能显示；训练可以继续，请收起后重新进入取景。",
            onCollapse: {},
            onPause: {},
            onComplete: {},
            onEdit: {},
            onMore: {}
        )
        .frame(width: size.width, height: size.height)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
        let data = try XCTUnwrap(image.pngData())
        let snapshotURL = FileManager.default.temporaryDirectory
            .appending(path: "SomaGuidedPortraitQA.png")
        try data.write(to: snapshotURL, options: .atomic)

        XCTAssertEqual(image.size, size)
        XCTAssertGreaterThan(data.count, 10000)
        window.isHidden = true
    }
}
