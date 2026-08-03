import AVFoundation
import SwiftUI
import UIKit

@MainActor
struct WorkoutCameraPreview: UIViewRepresentable {
    let camera: WorkoutCameraService

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera)
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.configure(uiView)
    }

    static func dismantleUIView(
        _ uiView: CameraPreviewView,
        coordinator: Coordinator
    ) {
        uiView.onPreviewLayerReady = nil
        if let layer = uiView.previewLayer {
            coordinator.camera?.detachPreviewLayer(layer)
        }
    }

    @MainActor
    final class Coordinator {
        weak var camera: WorkoutCameraService?

        init(camera: WorkoutCameraService) {
            self.camera = camera
        }

        func configure(_ view: CameraPreviewView) {
            view.onPreviewLayerReady = { [weak self] layer in
                self?.camera?.attachPreviewLayer(layer)
            }
            view.notifyPreviewLayerIfReady()
        }
    }
}

@MainActor
final class CameraPreviewView: UIView {
    var onPreviewLayerReady: (@MainActor (AVCaptureVideoPreviewLayer) -> Void)?

    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifyPreviewLayerIfReady()
    }

    func notifyPreviewLayerIfReady() {
        guard window != nil, let previewLayer else { return }
        onPreviewLayerReady?(previewLayer)
    }
}
