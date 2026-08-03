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
        if let layer = coordinator.camera?.sharedPreviewLayer {
            uiView.removePreviewLayerIfOwned(layer)
        }
    }

    @MainActor
    final class Coordinator {
        weak var camera: WorkoutCameraService?

        init(camera: WorkoutCameraService) {
            self.camera = camera
        }

        func configure(_ view: CameraPreviewView) {
            guard let camera else { return }
            let layer = camera.sharedPreviewLayer
            view.onPreviewLayerReady = { [weak self] layer in
                self?.camera?.attachPreviewLayer(layer)
            }
            view.installPreviewLayer(layer)
        }
    }
}

@MainActor
final class CameraPreviewView: UIView {
    var onPreviewLayerReady: (@MainActor (AVCaptureVideoPreviewLayer) -> Void)?
    private weak var hostedPreviewLayer: AVCaptureVideoPreviewLayer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifyPreviewLayerIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedPreviewLayer?.frame = bounds
    }

    func installPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard hostedPreviewLayer !== previewLayer
            || previewLayer.superlayer !== layer
        else {
            previewLayer.frame = bounds
            notifyPreviewLayerIfReady()
            return
        }

        previewLayer.removeFromSuperlayer()
        hostedPreviewLayer = previewLayer
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
        notifyPreviewLayerIfReady()
    }

    func removePreviewLayerIfOwned(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard previewLayer.superlayer === layer else { return }
        previewLayer.removeFromSuperlayer()
        if hostedPreviewLayer === previewLayer {
            hostedPreviewLayer = nil
        }
    }

    func notifyPreviewLayerIfReady() {
        guard window != nil, let hostedPreviewLayer else { return }
        onPreviewLayerReady?(hostedPreviewLayer)
    }
}
