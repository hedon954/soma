import SwiftUI

enum FoldedMediaLayout {
    static let cardWidth: CGFloat = 172
    static let minimumHeight: CGFloat = 116
    static let maximumHeight: CGFloat = 258
    static let portraitCardSize = CGSize(width: 150, height: 200)
    static let squareCardSize = CGSize(width: 160, height: 160)
    static let landscapeCardSize = CGSize(width: 172, height: 116)
    static let cornerRadius: CGFloat = 10
    static let layerScaleStep: CGFloat = 0.10
    static let middleLayerExposureRatio: CGFloat = 0.10
    static let backLayerExposureRatio: CGFloat = 0.165
    static let layerRotationStep: Double = 1.8

    static func cardHeight(forAspectRatio aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return cardWidth
        }
        return min(
            maximumHeight,
            max(minimumHeight, cardWidth / aspectRatio)
        )
    }

    static func scale(forLayer layer: Int) -> CGFloat {
        max(0.72, 1 - layerScaleStep * CGFloat(max(layer, 0)))
    }

    static func rotation(forLayer layer: Int) -> Double {
        layerRotationStep * Double(max(layer, 0))
    }

    static func foldedFrontSize(forAspectRatio aspectRatio: CGFloat) -> CGSize {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return squareCardSize
        }
        if aspectRatio < 0.90 {
            return portraitCardSize
        }
        if aspectRatio > 1.10 {
            return landscapeCardSize
        }
        return squareCardSize
    }

    static func scaledSize(
        forLayer layer: Int,
        frontSize: CGSize
    ) -> CGSize {
        let scale = scale(forLayer: layer)
        return CGSize(
            width: frontSize.width * scale,
            height: frontSize.height * scale
        )
    }

    static func targetExposure(
        forLayer layer: Int,
        frontWidth: CGFloat
    ) -> CGFloat {
        switch max(layer, 0) {
        case 0:
            0
        case 1:
            frontWidth * middleLayerExposureRatio
        default:
            frontWidth * backLayerExposureRatio
        }
    }

    static func rotatedBoundingWidth(
        forLayer layer: Int,
        size: CGSize
    ) -> CGFloat {
        let radians = rotation(forLayer: layer) * .pi / 180
        return size.width * abs(cos(radians)) +
            size.height * abs(sin(radians))
    }

    static func centerX(
        forLayer layer: Int,
        size: CGSize,
        frontSize: CGSize
    ) -> CGFloat {
        frontSize.width + targetExposure(
            forLayer: layer,
            frontWidth: frontSize.width
        ) -
            rotatedBoundingWidth(forLayer: layer, size: size) / 2
    }

    static func rightEdge(
        forLayer layer: Int,
        size: CGSize,
        frontSize: CGSize
    ) -> CGFloat {
        centerX(
            forLayer: layer,
            size: size,
            frontSize: frontSize
        ) +
            rotatedBoundingWidth(forLayer: layer, size: size) / 2
    }

    static func stackOverflowWidth(frontWidth: CGFloat) -> CGFloat {
        targetExposure(forLayer: 2, frontWidth: frontWidth)
    }
}

struct StoredMediaStrip: View {
    let attachments: [MediaAttachmentReference]

    @State private var isExpanded = false
    @State private var presentedAttachment: MediaAttachmentReference?

    var body: some View {
        Group {
            if attachments.count >= 3 {
                if isExpanded {
                    expandedGrid
                } else {
                    foldedCard
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        mediaButton(attachment) {
                            StoredMediaTile(attachment: attachment)
                                .frame(width: 132, height: 108)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 278, alignment: .trailing)
        .animation(.snappy(duration: 0.28), value: isExpanded)
        .fullScreenCover(item: $presentedAttachment) { attachment in
            MediaViewer(
                attachments: attachments,
                initialAttachmentID: attachment.id
            )
        }
    }

    private var foldedCard: some View {
        let backSize = foldedLayerSize(offset: 2)
        let middleSize = foldedLayerSize(offset: 1)

        return HStack(spacing: 10) {
            Button {
                isExpanded = true
            } label: {
                Text("展开 \(attachments.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 32)
                    .background(
                        Color.black.opacity(0.065),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开 \(attachments.count) 个媒体附件")

            ZStack(alignment: .topLeading) {
                StoredMediaTile(
                    attachment: foldedAttachment(offset: 2),
                    cornerRadius: FoldedMediaLayout.cornerRadius
                )
                .frame(
                    width: backSize.width,
                    height: backSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FoldedMediaLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .rotationEffect(
                    .degrees(FoldedMediaLayout.rotation(forLayer: 2)),
                    anchor: .center
                )
                .position(
                    x: FoldedMediaLayout.centerX(
                        forLayer: 2,
                        size: backSize,
                        frontSize: foldedFrontSize
                    ),
                    y: foldedCardHeight / 2
                )

                StoredMediaTile(
                    attachment: foldedAttachment(offset: 1),
                    cornerRadius: FoldedMediaLayout.cornerRadius
                )
                .frame(
                    width: middleSize.width,
                    height: middleSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FoldedMediaLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .rotationEffect(
                    .degrees(FoldedMediaLayout.rotation(forLayer: 1)),
                    anchor: .center
                )
                .position(
                    x: FoldedMediaLayout.centerX(
                        forLayer: 1,
                        size: middleSize,
                        frontSize: foldedFrontSize
                    ),
                    y: foldedCardHeight / 2
                )

                StoredMediaTile(
                    attachment: foldedAttachment(offset: 0),
                    cornerRadius: FoldedMediaLayout.cornerRadius
                )
                .frame(
                    width: foldedFrontSize.width,
                    height: foldedFrontSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FoldedMediaLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .position(
                    x: foldedFrontSize.width / 2,
                    y: foldedCardHeight / 2
                )
            }
            .frame(
                width: foldedFrontSize.width +
                    FoldedMediaLayout.stackOverflowWidth(
                        frontWidth: foldedFrontSize.width
                    ),
                height: foldedCardHeight,
                alignment: .topLeading
            )
            .contentShape(Rectangle())
            .onTapGesture {
                presentedAttachment = foldedAttachment(offset: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("放大第一项媒体附件")
            .accessibilityHint("使用展开按钮可查看全部附件")
            .accessibilityAddTraits(.isButton)
        }
    }

    private var expandedGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                isExpanded = false
            } label: {
                Text("收起")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 32)
                    .background(
                        Color.black.opacity(0.065),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, max(0, (foldedCardHeight - 32) / 2))
            .accessibilityLabel("收起媒体附件")

            LazyVStack(alignment: .trailing, spacing: 14) {
                ForEach(attachments) { attachment in
                    mediaButton(attachment) {
                        StoredMediaTile(
                            attachment: attachment,
                            cornerRadius: FoldedMediaLayout.cornerRadius
                        )
                        .frame(
                            width: FoldedMediaLayout.cardWidth,
                            height: cardHeight(for: attachment)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: FoldedMediaLayout.cornerRadius,
                                style: .continuous
                            )
                        )
                    }
                }
            }
        }
    }

    private func mediaButton(
        _ attachment: MediaAttachmentReference,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button {
            presentedAttachment = attachment
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            attachment.kind == .video
                ? "播放视频附件"
                : "放大图片附件"
        )
    }

    private var foldedCardHeight: CGFloat {
        foldedFrontSize.height
    }

    private var foldedFrontSize: CGSize {
        FoldedMediaLayout.foldedFrontSize(
            forAspectRatio: aspectRatio(for: attachments[0])
        )
    }

    private func foldedLayerSize(offset: Int) -> CGSize {
        FoldedMediaLayout.scaledSize(
            forLayer: offset,
            frontSize: foldedFrontSize
        )
    }

    private func cardHeight(for attachment: MediaAttachmentReference) -> CGFloat {
        FoldedMediaLayout.cardHeight(
            forAspectRatio: aspectRatio(for: attachment)
        )
    }

    private func aspectRatio(
        for attachment: MediaAttachmentReference
    ) -> CGFloat {
        guard attachment.kind == .image,
              let image = MediaStore.image(at: attachment.path),
              image.size.width > 0,
              image.size.height > 0
        else {
            return 1
        }

        return image.size.width / image.size.height
    }

    private func foldedAttachment(offset: Int) -> MediaAttachmentReference {
        attachments[offset]
    }
}

private struct StoredMediaTile: View {
    let attachment: MediaAttachmentReference
    var cornerRadius: CGFloat = 14

    var body: some View {
        Group {
            if attachment.kind == .image {
                LocalImageView(path: attachment.path)
            } else {
                VideoPosterView(path: attachment.path, badgeFont: .title2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}
