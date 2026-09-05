import Photos
import SwiftData
import SwiftUI
import UIKit

private final class SendableWorkoutShareImage: @unchecked Sendable {
    let image: UIImage

    init(_ image: UIImage) {
        self.image = image
    }
}

private enum WorkoutShareRenderError: Error {
    case encodingFailed
}

struct WorkoutShareSheet: View {
    let model: WorkoutSharePosterModel
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var isRendering = false
    @State private var renderID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let renderedImage {
                        Image(uiImage: renderedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            // PRD 020：长按菜单只保留拷贝；保存用主按钮、分享用工具栏。
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.image = renderedImage
                                } label: {
                                    Label("拷贝图片", systemImage: "doc.on.doc")
                                }
                            }
                            .accessibilityLabel("训练分享海报")
                            .accessibilityValue(model.exercises.map { "\($0.name)，\($0.loadSummary)" }.joined(separator: "。"))
                            .accessibilityHint("长按可拷贝图片")
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label(
                                "无法生成分享图",
                                systemImage: "exclamationmark.triangle"
                            )
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("重新生成") {
                                Task { await renderPoster() }
                            }
                            .appPrimaryButtonStyle()
                            Button("返回训练") {
                                dismiss()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        ProgressView("正在生成海报…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    }

                    if let renderedImage {
                        Button {
                            Task { await saveToPhotos(renderedImage) }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("保存到相册", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .appPrimaryButtonStyle()
                        .disabled(isSaving)
                    }

                    if model.recordedWeightMissing {
                        NavigationLink {
                            PersonalBodyInfoView()
                        } label: {
                            Label(
                                "补充体重后，之后的训练可估算消耗",
                                systemImage: "flame"
                            )
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                AppTheme.warningSoftTint,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .foregroundStyle(AppTheme.warning)
                    }

                    Text("海报在本机渲染，不含照片、视频或位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.pageBackground)
            .toolbarBackground(AppTheme.pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("分享训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareURL, renderedImage != nil {
                        ShareLink(
                            item: shareURL,
                            preview: SharePreview(
                                "Soma 训练海报",
                                image: Image(uiImage: renderedImage ?? UIImage())
                            )
                        ) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    } else if isRendering {
                        ProgressView()
                    }
                }
            }
            .task {
                await renderPoster()
            }
            .alert(
                "保存图片",
                isPresented: Binding(
                    get: { saveMessage != nil },
                    set: {
                        if !$0 {
                            saveMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveMessage ?? "")
            }
        }
    }

    @MainActor
    private func renderPoster() async {
        let currentRenderID = UUID()
        renderID = currentRenderID
        isRendering = true
        errorMessage = nil
        defer {
            if renderID == currentRenderID {
                isRendering = false
            }
        }
        let poster = WorkoutSharePosterView(model: model)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = max(UIScreen.main.scale, 2)
        guard let image = renderer.uiImage else {
            errorMessage = "本机渲染失败，请稍后重试。"
            return
        }
        let imageBox = SendableWorkoutShareImage(image)
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                guard let data = imageBox.image.pngData() else {
                    throw WorkoutShareRenderError.encodingFailed
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "soma-workout-share-\(UUID().uuidString).png"
                    )
                try data.write(to: url, options: .atomic)
                return url
            }.value
            guard !Task.isCancelled, renderID == currentRenderID else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            renderedImage = image
            shareURL = url
        } catch {
            guard !Task.isCancelled, renderID == currentRenderID else { return }
            errorMessage = "无法保存分享图片。"
        }
    }

    @MainActor
    private func saveToPhotos(_ image: UIImage) async {
        isSaving = true
        defer { isSaving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = "没有相册写入权限。请在系统设置中允许 Soma 添加照片。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveMessage = "已保存到相册。"
        } catch {
            saveMessage = "保存失败，请稍后重试。"
        }
    }
}
