import AVFoundation
import SwiftUI
import UIKit

/// 视频缩略统一用「有画面的一帧 + 播放角标」呈现，不再显示纯黑占位。
/// 帧取自视频前段（跳过可能全黑的首帧），生成结果按路径缓存。
struct VideoPosterView: View {
    let path: String?
    var badgeFont: Font = .title3

    @State private var poster: UIImage?

    var body: some View {
        ZStack {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
            } else {
                AppTheme.softTint
            }
            Image(systemName: "play.circle.fill")
                .font(badgeFont)
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.45), radius: 4)
        }
        .clipped()
        .task(id: path) {
            poster = await VideoPosterStore.poster(for: path)
        }
        .accessibilityHidden(true)
    }
}

enum VideoPosterStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func poster(for path: String?) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        guard let url = MediaStore.url(at: path) else { return nil }
        guard let image = await generatePoster(from: url) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    private static func generatePoster(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite,
              duration.seconds > 0
        else {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        // 允许在附近取帧，命中关键帧即可，避免精确 seek 的解码开销。
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let second = min(max(duration.seconds * 0.1, 0.3), duration.seconds)
        let time = CMTime(seconds: second, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
