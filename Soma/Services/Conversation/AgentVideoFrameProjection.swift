import Foundation
import SwiftOpenAI

@MainActor
final class AgentVideoFallbackState {
    var isActive: Bool
    var frames: [VideoFrameSet]?
    var appliedToMessages = false

    init(isActive: Bool = false) {
        self.isActive = isActive
    }
}

enum AgentVideoFrameProjection {
    static func applying(
        _ frames: [VideoFrameSet],
        videos: [AgentVideoInput],
        to messages: [ChatCompletionParameters.Message]
    ) throws -> [ChatCompletionParameters.Message] {
        guard frames.count == videos.count,
              let lastUser = messages.lastIndex(where: { $0.role == "user" })
        else {
            throw VideoFrameFallbackError.invalidMessage
        }
        try VideoFrameFallbackPolicy.validate(frames)
        var result = messages
        for (video, set) in zip(videos, frames) {
            let index = video.messageIndex ?? lastUser
            guard result.indices.contains(index), result[index].role == "user" else {
                throw VideoFrameFallbackError.invalidMessage
            }
            var parts: [ChatCompletionParameters.Message.ContentType.MessageContent] = switch result[index].content {
            case let .text(text): [.text(text)]
            case let .contentArray(content): content
            }
            parts.append(.text(prompt(for: set)))
            for (data, timestamp) in zip(set.frames, set.timestampsSeconds) {
                guard let url = URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())") else {
                    throw VideoFrameFallbackError.cannotDecode
                }
                parts.append(.text("视频画面：\(timestamp.formatted(.number.precision(.fractionLength(2)))) 秒"))
                parts.append(.imageUrl(.init(url: url, detail: "auto")))
            }
            result[index] = .init(role: .user, content: .contentArray(parts))
        }
        return result
    }

    static func prompt(for set: VideoFrameSet) -> String {
        """
        [SOMA VIDEO FRAME FALLBACK v1]
        当前模型不支持完整视频，本条消息的视频改用 \(set.frames.count) 张画面输入，覆盖 \(set.durationSeconds.formatted()) 秒。
        本说明替代此前完整视频直传说明。原视频保留在设备；本次模型只获得静态画面，不能声称观看了完整视频，
        不能据此确定完整动作节奏、速度或连续轨迹。仍遵循本轮原有授权和已有工具结果，不重复写入。
        """
    }
}
