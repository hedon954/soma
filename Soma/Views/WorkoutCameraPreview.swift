import AVFoundation
import SwiftUI
import UIKit

@MainActor
struct WorkoutCameraPreview: UIViewRepresentable {
    let camera: WorkoutCameraService
    let videoGravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera, videoGravity: videoGravity)
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: .zero)
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
        if let camera = coordinator.camera {
            let layer = camera.sharedPreviewLayer
            camera.detachPreviewLayer(
                layer,
                hostID: uiView.previewHostID
            )
            uiView.removePreviewLayerIfOwned(layer)
        }
    }

    @MainActor
    final class Coordinator {
        weak var camera: WorkoutCameraService?

        func configure(_ view: CameraPreviewView) {
            guard let camera else { return }
            let layer = camera.sharedPreviewLayer
            view.onPreviewLayerReady = { [weak self] layer, hostID in
                self?.camera?.attachPreviewLayer(
                    layer,
                    hostID: hostID,
                    videoGravity: self?.videoGravity ?? .resizeAspectFill
                )
            }
            view.installPreviewLayer(layer, videoGravity: videoGravity)
        }

        private let videoGravity: AVLayerVideoGravity

        init(camera: WorkoutCameraService, videoGravity: AVLayerVideoGravity) {
            self.camera = camera
            self.videoGravity = videoGravity
        }
    }
}

@MainActor
final class CameraPreviewView: UIView {
    let previewHostID = UUID()
    var onPreviewLayerReady:
        (@MainActor (AVCaptureVideoPreviewLayer, UUID) -> Void)?
    private weak var hostedPreviewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifyPreviewLayerIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedPreviewLayer?.frame = bounds
    }

    func installPreviewLayer(
        _ previewLayer: AVCaptureVideoPreviewLayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        if hostedPreviewLayer === previewLayer {
            if previewLayer.superlayer === layer {
                previewLayer.frame = bounds
                previewLayer.videoGravity = videoGravity
                notifyPreviewLayerIfReady()
            }
            return
        }

        previewLayer.removeFromSuperlayer()
        hostedPreviewLayer = previewLayer
        previewLayer.frame = bounds
        previewLayer.videoGravity = videoGravity
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
