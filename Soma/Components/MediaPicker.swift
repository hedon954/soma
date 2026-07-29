import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PickedMedia {
    case image(Data)
    case video(URL)
}

struct MediaPicker: UIViewControllerRepresentable {
    enum Source { case camera, library }

    let source: Source
    let allowsVideo: Bool
    let onPick: (PickedMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                return makeLibrary(context: context)
            }
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            picker.mediaTypes = allowsVideo
                ? [UTType.image.identifier, UTType.movie.identifier]
                : [UTType.image.identifier]
            picker.videoMaximumDuration = 90
            picker.videoQuality = .typeMedium
            return picker
        case .library:
            return makeLibrary(context: context)
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private func makeLibrary(context: Context) -> UIViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = allowsVideo ? .any(of: [.images, .videos]) : .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let onPick: (PickedMedia) -> Void
        let dismissAction: DismissAction

        init(onPick: @escaping (PickedMedia) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            dismissAction = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismissAction()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.84)
            {
                onPick(.image(data))
            } else if let url = info[.mediaURL] as? URL {
                onPick(.video(url))
            }
            dismissAction()
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                dismissAction()
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                    guard let self, let url else { return }
                    let temp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                    try? FileManager.default.copyItem(at: url, to: temp)
                    DispatchQueue.main.async {
                        self.onPick(.video(temp))
                        self.dismissAction()
                    }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                    guard let self, let data else { return }
                    DispatchQueue.main.async {
                        self.onPick(.image(data))
                        self.dismissAction()
                    }
                }
            }
        }
    }
}

struct MediaSourceDialog: View {
    let allowsVideo: Bool
    let onPick: (PickedMedia) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination: PickerDestination?

    enum PickerDestination: String, Identifiable {
        case camera, library
        var id: String {
            rawValue
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                sourceButton(
                    title: allowsVideo ? "拍照或录像" : "拍照",
                    subtitle: "使用设备相机",
                    icon: "camera.fill",
                    destination: .camera
                )
                sourceButton(
                    title: "从照片选择",
                    subtitle: allowsVideo ? "支持图片和视频" : "支持图片",
                    icon: "photo.on.rectangle.angled",
                    destination: .library
                )
                Spacer()
                Label("媒体只保存在此设备；启用远程 AI 时，仅分析内容会发送给已配置的模型服务。", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .padding()
            .navigationTitle("添加媒体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(item: $destination) { destination in
                MediaPicker(
                    source: destination == .camera ? .camera : .library,
                    allowsVideo: allowsVideo
                ) { media in
                    onPick(media)
                    dismiss()
                }
                .ignoresSafeArea()
            }
        }
        .presentationDetents([.medium])
    }

    private func sourceButton(
        title: String,
        subtitle: String,
        icon: String,
        destination: PickerDestination
    ) -> some View {
        Button {
            self.destination = destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(AppTheme.tint)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.softTint, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
