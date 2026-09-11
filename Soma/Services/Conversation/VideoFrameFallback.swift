@preconcurrency import AVFoundation
import Foundation
import UIKit

struct VideoFrameSet: Equatable, Sendable {
    let frames: [Data]
    let timestampsSeconds: [Double]
    let durationSeconds: Double
}

enum VideoFrameFallbackError: LocalizedError {
    case cannotDecode
    case budgetExceeded
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .cannotDecode:
            "当前模型不支持完整视频，且未能提取可用画面。原视频仍保留，请换一个可播放的视频，或选择支持视频的模型后重试。"
        case .budgetExceeded:
            "这次视频太多或画面体积超出分析上限。请分开发送视频，或选择支持完整视频的模型后重试。"
        case .invalidMessage:
            "无法找到这次视频对应的消息。请重新选择或发送视频；原附件仍保留。"
        }
    }
}

enum VideoFrameFallbackPolicy {
    static let maximumFrames = 24
    static let minimumFramesPerVideo = 8
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumDimension = 768

    static func frameCounts(durations: [Double]) throws -> [Int] {
        guard !durations.isEmpty, durations.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw VideoFrameFallbackError.cannotDecode
        }
        guard durations.count <= maximumFrames / minimumFramesPerVideo else {
            throw VideoFrameFallbackError.budgetExceeded
        }
        let desired = durations.map { Int(min(24, max(8, ceil($0 * 2)))) }
        var counts = durations.map { _ in minimumFramesPerVideo }
        while counts.reduce(0, +) < maximumFrames {
            var added = false
            for index in counts.indices where counts[index] < desired[index] {
                counts[index] += 1
                added = true
                if counts.reduce(0, +) == maximumFrames {
                    break
                }
            }
            if !added {
                break
            }
        }
        return counts
    }

    static func timestamps(duration: Double, count: Int) -> [Double] {
        guard duration.isFinite, duration > 0, count >= minimumFramesPerVideo, count <= maximumFrames else { return [] }
        // 包括开头和接近结尾的画面；不请求恰好位于文件终点的不存在帧。
        let finalTime = max(0, duration - min(0.04, duration / 10))
        return (0 ..< count).map { finalTime * Double($0) / Double(count - 1) }
    }

    static func validate(_ sets: [VideoFrameSet]) throws {
        let count = sets.reduce(0) { $0 + $1.frames.count }
        let bytes = sets.reduce(0) { $0 + $1.frames.reduce(0) { $0 + $1.count } }
        guard !sets.isEmpty, count <= maximumFrames, bytes <= maximumBytes else {
            throw VideoFrameFallbackError.budgetExceeded
        }
        guard sets.allSatisfy({ set in
            set.durationSeconds.isFinite && set.durationSeconds > 0
                && set.frames.count >= minimumFramesPerVideo && set.frames.count == set.timestampsSeconds.count
                && set.frames.allSatisfy { !$0.isEmpty }
                && set.timestampsSeconds.allSatisfy { $0.isFinite && $0 >= 0 && $0 < set.durationSeconds }
                && zip(set.timestampsSeconds, set.timestampsSeconds.dropFirst()).allSatisfy { pair in pair.0 <= pair.1 }
        }) else { throw VideoFrameFallbackError.cannotDecode }
    }
}

enum VideoFrameFallbackPreparer {
    static func prepare(_ videos: [AgentVideoInput]) async throws -> [VideoFrameSet] {
        try Task.checkCancellation()
        guard !videos.isEmpty else { throw VideoFrameFallbackError.cannotDecode }
        if videos.allSatisfy({ $0.frameFallback != nil }) {
            let sets = videos.compactMap(\.frameFallback)
            try VideoFrameFallbackPolicy.validate(sets)
            return sets
        }
        var temporaryURLs: [URL] = []
        defer { for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        } }
        var assets: [AVURLAsset] = []
        var durations: [Double] = []
        for video in videos {
            try Task.checkCancellation()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("soma-frames-\(UUID().uuidString).mp4")
            temporaryURLs.append(url)
            try video.data.write(to: url, options: .atomic)
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration),
                  duration.seconds.isFinite, duration.seconds > 0
            else {
                throw VideoFrameFallbackError.cannotDecode
            }
            assets.append(asset)
            durations.append(duration.seconds)
        }
        let counts = try VideoFrameFallbackPolicy.frameCounts(durations: durations)
        var result: [VideoFrameSet] = []
        var totalBytes = 0
        for index in assets.indices {
            let generator = AVAssetImageGenerator(asset: assets[index])
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: VideoFrameFallbackPolicy.maximumDimension,
                                           height: VideoFrameFallbackPolicy.maximumDimension)
            let cancellable = CancellableImageGenerator(generator)
            let times = VideoFrameFallbackPolicy.timestamps(duration: durations[index], count: counts[index])
            let set = try await withTaskCancellationHandler {
                defer { generator.cancelAllCGImageGeneration() }
                var frames: [Data] = []
                var actualTimes: [Double] = []
                for seconds in times {
                    try Task.checkCancellation()
                    let frame: (image: CGImage, actualTime: CMTime)
                    do {
                        frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                    } catch {
                        try Task.checkCancellation()
                        throw VideoFrameFallbackError.cannotDecode
                    }
                    guard let data = UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.7),
                          !data.isEmpty else { throw VideoFrameFallbackError.cannotDecode }
                    totalBytes += data.count
                    guard totalBytes <= VideoFrameFallbackPolicy.maximumBytes else {
                        throw VideoFrameFallbackError.budgetExceeded
                    }
                    frames.append(data)
                    actualTimes.append(frame.actualTime.seconds)
                }
                return VideoFrameSet(frames: frames, timestampsSeconds: actualTimes, durationSeconds: durations[index])
            } onCancel: {
                cancellable.value.cancelAllCGImageGeneration()
            }
            result.append(set)
        }
        try Task.checkCancellation()
        try VideoFrameFallbackPolicy.validate(result)
        return result
    }
}

private final class CancellableImageGenerator: @unchecked Sendable {
    let value: AVAssetImageGenerator
    init(_ value: AVAssetImageGenerator) {
        self.value = value
    }
}
