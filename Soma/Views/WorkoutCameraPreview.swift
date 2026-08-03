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
            view.onPreviewLayerReady = { [weak self] layer, hostID in
                self?.camera?.attachPreviewLayer(layer, hostID: hostID)
            }
            view.installPreviewLayer(layer)
        }
    }
}

@MainActor
final class CameraPreviewView: UIView {
    let previewHostID = UUID()
    var onPreviewLayerReady:
        (@MainActor (AVCaptureVideoPreviewLayer, UUID) -> Void)?
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
        if hostedPreviewLayer === previewLayer {
            if previewLayer.superlayer === layer {
                previewLayer.frame = bounds
                notifyPreviewLayerIfReady()
            }
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
        onPreviewLayerReady?(hostedPreviewLayer, previewHostID)
    }
}
