import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PickedMedia {
    case image(Data)
    case video(URL)
}

struct MediaPicker: UIViewControllerRepresentable {
    static let maximumSelectionCount = 10

    enum Source: Equatable { case camera, library }

    let source: Source
    let allowsVideo: Bool
    let selectionLimit: Int
    let onPick: ([PickedMedia]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        source: Source,
        allowsVideo: Bool,
        selectionLimit: Int = Self.maximumSelectionCount,
        onPick: @escaping ([PickedMedia]) -> Void
    ) {
        self.source = source
        self.allowsVideo = allowsVideo
        self.selectionLimit = max(1, min(selectionLimit, Self.maximumSelectionCount))
        self.onPick = onPick
    }

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
        configuration.selectionLimit = selectionLimit
        configuration.filter = allowsVideo ? .any(of: [.images, .videos]) : .images
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let onPick: ([PickedMedia]) -> Void
        let dismissAction: DismissAction

        init(onPick: @escaping ([PickedMedia]) -> Void, dismiss: DismissAction) {
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
                onPick([.image(data)])
            } else if let url = info[.mediaURL] as? URL {
                onPick([.video(url)])
            }
            dismissAction()
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                dismissAction()
                return
            }

            let accumulator = MediaResultAccumulator(count: results.count)
            let group = DispatchGroup()
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                group.enter()
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url else { return }
                        let temp = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                        do {
                            try FileManager.default.copyItem(at: url, to: temp)
                            accumulator.store(.video(temp), at: index)
                        } catch {
                            return
                        }
                    }
                } else {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        defer { group.leave() }
                        guard let data else { return }
                        accumulator.store(.image(data), at: index)
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                let media = accumulator.values
                if !media.isEmpty {
                    onPick(media)
                }
                dismissAction()
            }
        }
    }
}

private final class MediaResultAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PickedMedia?]

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func store(_ media: PickedMedia, at index: Int) {
        lock.lock()
        storage[index] = media
        lock.unlock()
    }

    var values: [PickedMedia] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { $0 }
    }
}

struct MediaSourceDialog: View {
    let allowsVideo: Bool
    let selectionLimit: Int
    let initialSource: MediaPicker.Source?
    let privacyMessage: String
    let onPick: ([PickedMedia]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination: PickerDestination?

    enum PickerDestination: String, Identifiable {
        case camera, library
        var id: String {
            rawValue
        }
    }

    init(
        allowsVideo: Bool,
        selectionLimit: Int = MediaPicker.maximumSelectionCount,
        initialSource: MediaPicker.Source? = nil,
        privacyMessage: String = "媒体原件保存在此设备；只有点击发送后，分析所需内容才会交给已配置的模型服务。",
        onPick: @escaping ([PickedMedia]) -> Void
    ) {
        self.allowsVideo = allowsVideo
        self.selectionLimit = max(1, min(selectionLimit, MediaPicker.maximumSelectionCount))
        self.initialSource = initialSource
        self.privacyMessage = privacyMessage
        self.onPick = onPick
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
                    title: "从照片与视频中选择",
                    subtitle: allowsVideo
                        ? "最多 \(selectionLimit) 项，可混合选择"
                        : "最多 \(selectionLimit) 张图片",
                    icon: "photo.on.rectangle.angled",
                    destination: .library
                )
                Spacer()
                Label(privacyMessage, systemImage: "lock.shield")
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
                    allowsVideo: allowsVideo,
                    selectionLimit: selectionLimit
                ) { media in
                    onPick(media)
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .task {
                guard destination == nil, let initialSource else { return }
                await Task.yield()
                destination = initialSource == .camera ? .camera : .library
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
