import Foundation
import ImageIO

struct PreparedAgentHistory {
    var projection: ConversationContextProjection
    var history: [AgentConversationExchange]
    var preparationMilliseconds: Int
    var missingReferencedTurn = false

    var mediaPreparationFailure: ConversationMediaPreparationError? {
        missingReferencedTurn ? .historicalAttachmentUnavailable : history.lazy.compactMap(\.mediaPreparationFailure).first
    }
}

extension ConversationProcessingService {
    func mediaDisplaySummary(
        _ attachments: [MediaAttachmentReference]
    ) -> String {
        let imageCount = attachments.count { $0.kind == .image }
        let videoCount = attachments.count { $0.kind == .video }
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "发送了媒体" : "发送了" + parts.joined(separator: "和")
    }

    nonisolated func prepareStoredMedia(
        _ attachments: [MediaAttachmentReference],
        frameLimit: Int,
        directVideoCapability: DirectVideoCapability? = .standard
    ) async -> PreparedConversationMedia {
        var images: [Data] = []
        let imageAttachments = attachments.filter { $0.kind == .image }
        let videoAttachments = attachments.filter { $0.kind == .video }
        let videoCount = videoAttachments.count
        let imageLimit = max(0, frameLimit)
        var failure: ConversationMediaPreparationError? = imageAttachments.count > imageLimit ? .imageLimitExceeded : nil
        for attachment in imageAttachments.prefix(imageLimit) {
            guard let url = MediaStore.url(at: attachment.path), let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0
            else {
                failure = .attachmentUnavailable
                continue
            }
            images.append(data)
        }
        var videos: [AgentVideoInput] = []
        if failure == nil, let directVideoCapability {
            for attachment in videoAttachments {
                guard let url = MediaStore.url(at: attachment.path) else {
                    failure = .attachmentUnavailable
                    break
                }
                guard let input = await DirectVideoPreparer.input(for: url, capability: directVideoCapability) else {
                    failure = .fullVideoUnavailable
                    break
                }
                videos.append(input)
            }
        }
        if failure == nil, videos.count != videoCount {
            failure = .nativeVideoUnsupported
        }
        if failure != nil {
            videos = []
        }
        let mode: AgentMediaMode = if !videos.isEmpty {
            .directVideo
        } else if !images.isEmpty {
            .images
        } else {
            .text
        }
        return PreparedConversationMedia(
            attachments: attachments,
            frames: images,
            videos: videos,
            imageCount: imageAttachments.count,
            videoCount: videoCount,
            mode: mode,
            preparationFailure: failure
        )
    }

    func directVideoCapability(
        for userMessage: CoachMessage,
        attachments: [MediaAttachmentReference],
        context: ConversationProcessingContext
    ) -> DirectVideoCapability? {
        guard attachments.contains(where: { $0.kind == .video }) else {
            return nil
        }
        let route = context.ai.route(
            text: userMessage.text,
            hasMedia: !attachments.isEmpty,
            hasVideo: true
        )
        let assessment = context.ai.modelMultimodalAssessment(
            provider: route.provider,
            baseURL: route.baseURL,
            model: route.model
        )
        return assessment.support == .unsupported ? nil : .standard
    }
}
