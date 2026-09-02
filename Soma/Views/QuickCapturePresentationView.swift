import AVFoundation
import SwiftUI
import UIKit

struct QuickCapturePresentationView: View {
    let presentation: CapturePresentation
    let onPick: ([PickedMedia]) -> Void
    let onCancel: () -> Void

    @State private var source: MediaPicker.Source
    @State private var cameraState = CameraAvailabilityState.checking

    init(
        presentation: CapturePresentation,
        onPick: @escaping ([PickedMedia]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.onPick = onPick
        self.onCancel = onCancel
        _source = State(initialValue: presentation.mode == .camera ? .camera : .library)
    }

    var body: some View {
        Group {
            if source == .library {
                picker(source: .library)
            } else {
                switch cameraState {
                case .checking:
                    ProgressView("正在准备相机…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.pageBackground)
                case .available:
                    picker(source: .camera)
                case .denied:
                    cameraFallback(
                        title: "无法使用相机",
                        message: "请在系统设置中允许 Soma 使用相机，或改为从照片中选择。",
                        showsSettings: true
                    )
                case .unavailable:
                    cameraFallback(
                        title: "此设备没有可用相机",
                        message: "你仍可从照片与视频中选择内容。",
                        showsSettings: false
                    )
                }
            }
        }
        .task(id: source) {
            guard source == .camera else { return }
            cameraState = await CameraAvailabilityState.resolve()
        }
    }

    private func picker(source: MediaPicker.Source) -> some View {
        MediaPicker(
            source: source,
            allowsVideo: true,
            selectionLimit: MediaPicker.maximumSelectionCount,
            onCancel: onCancel,
            onPick: onPick
        )
        .ignoresSafeArea()
    }

    private func cameraFallback(
        title: String,
        message: String,
        showsSettings: Bool
    ) -> some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "camera.fill")
            } description: {
                Text(message)
            } actions: {
                VStack(spacing: 12) {
                    Button("选择照片与视频") {
                        source = .library
                    }
                    .appPrimaryButtonStyle()
                    if showsSettings {
                        Button("前往设置") {
                            guard let url = URL(
                                string: UIApplication.openSettingsURLString
                            ) else { return }
                            UIApplication.shared.open(url)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("取消", role: .cancel, action: onCancel)
                }
            }
            .navigationTitle("快速记录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum CameraAvailabilityState: Equatable {
    case checking
    case available
    case denied
    case unavailable

    @MainActor
    static func resolve() async -> Self {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .available
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
                ? .available
                : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
