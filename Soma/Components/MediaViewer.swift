import AVKit
import SwiftUI

struct MediaViewer: View {
    @Environment(\.dismiss) private var dismiss

    let deletionTitle: String?
    let deletionMessage: String?
    let onDelete: ((MediaAttachmentReference) -> Void)?

    @State private var attachments: [MediaAttachmentReference]
    @State private var selectedAttachmentID: String
    @State private var pendingDeletion: MediaAttachmentReference?

    init(
        attachments: [MediaAttachmentReference],
        initialAttachmentID: String,
        deletionTitle: String? = nil,
        deletionMessage: String? = nil,
        onDelete: ((MediaAttachmentReference) -> Void)? = nil
    ) {
        self.deletionTitle = deletionTitle
        self.deletionMessage = deletionMessage
        self.onDelete = onDelete
        _attachments = State(initialValue: attachments)
        _selectedAttachmentID = State(initialValue: initialAttachmentID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedAttachmentID) {
                ForEach(attachments) { attachment in
                    MediaViewerPage(attachment: attachment)
                        .tag(attachment.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("关闭媒体查看")

                    Spacer()

                    if attachments.count > 1 {
                        Text("\(selectedPosition + 1) / \(attachments.count)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Spacer()

                    if onDelete != nil {
                        Button(role: .destructive) {
                            pendingDeletion = selectedAttachment
                        } label: {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .foregroundStyle(.red)
                        .accessibilityLabel(
                            selectedAttachment?.kind == .video
                                ? "删除当前视频"
                                : "删除当前照片"
                        )
                    } else {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .alert(
            deletionTitle ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: {
                    if !$0 {
                        pendingDeletion = nil
                    }
                }
            ),
            presenting: pendingDeletion
        ) { attachment in
            Button("移除", role: .destructive) {
                delete(attachment)
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { _ in
            Text(deletionMessage ?? "")
        }
    }

    private var selectedAttachment: MediaAttachmentReference? {
        attachments.first { $0.id == selectedAttachmentID }
            ?? attachments.first
    }

    private var selectedPosition: Int {
        guard let selectedAttachment else { return 0 }
        return attachments.firstIndex(of: selectedAttachment) ?? 0
    }

    private func delete(_ attachment: MediaAttachmentReference) {
        let removedIndex = attachments.firstIndex(of: attachment) ?? 0
        onDelete?(attachment)
        attachments.removeAll { $0.id == attachment.id }
        pendingDeletion = nil

        guard !attachments.isEmpty else {
            dismiss()
            return
        }
        selectedAttachmentID = attachments[min(removedIndex, attachments.count - 1)].id
    }
}

private struct MediaViewerPage: View {
    let attachment: MediaAttachmentReference

    var body: some View {
        Group {
            switch attachment.kind {
            case .image:
                ZoomableLocalImage(path: attachment.path)
            case .video:
                MediaViewerVideo(path: attachment.path)
            case .none:
                ContentUnavailableView("媒体不可用", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 72)
    }
}

private struct ZoomableLocalImage: View {
    let path: String

    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    var body: some View {
        if let image = MediaStore.image(at: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(min(max(scale * gestureScale, 1), 4))
                .gesture(
                    MagnifyGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            scale = min(max(scale * value.magnification, 1), 4)
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        scale = scale > 1 ? 1 : 2
                    }
                }
                .accessibilityLabel("放大的照片")
                .accessibilityHint("双击切换缩放")
        } else {
            ContentUnavailableView("照片不可用", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(.white)
        }
    }
}

private struct MediaViewerVideo: View {
    @State private var player: AVPlayer?

    init(path: String) {
        _player = State(initialValue: MediaStore.url(at: path).map { AVPlayer(url: $0) })
    }

    var body: some View {
        if let player {
            VideoPlayer(player: player)
                .onDisappear { player.pause() }
        } else {
            ContentUnavailableView("视频不可用", systemImage: "video.slash")
                .foregroundStyle(.white)
        }
    }
}
