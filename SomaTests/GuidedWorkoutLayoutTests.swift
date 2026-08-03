import AVFoundation
@testable import Soma
import SwiftUI
import XCTest

final class GuidedWorkoutLayoutTests: XCTestCase {
    @MainActor
    func testPreviewUsesCaptureExactAspectFit() throws {
        let camera = WorkoutCameraService()
        let view = CameraPreviewView(frame: .zero)
        let layer = try XCTUnwrap(view.previewLayer)

        camera.attachPreviewLayer(layer)

        XCTAssertEqual(layer.videoGravity, .resizeAspect)
        camera.detachPreviewLayer(layer)
    }

    @MainActor
    func testPreviewLayerBecomesReadyOnlyAfterEnteringWindow() {
        let view = CameraPreviewView(frame: .zero)
        var readyLayers: [AVCaptureVideoPreviewLayer] = []
        view.onPreviewLayerReady = { readyLayers.append($0) }

        XCTAssertTrue(readyLayers.isEmpty)

        let controller = UIViewController()
        controller.view.addSubview(view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        view.frame = controller.view.bounds
        view.layoutIfNeeded()

        XCTAssertEqual(readyLayers.count, 1)
        XCTAssertTrue(readyLayers[0] === view.previewLayer)
        window.isHidden = true
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
    }

    @MainActor
    func testVisibleCountdownPublishesCompletionAtDeadline() async {
        let completed = expectation(description: "倒计时结束")
        let view = GuidedSetCountdownView(
            set: nil,
            targetText: "5 次",
            phaseStartedAt: .now.addingTimeInterval(-4),
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
}
