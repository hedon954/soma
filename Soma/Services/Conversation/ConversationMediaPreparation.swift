import Foundation

struct PreparedAgentHistory {
    var projection: ConversationContextProjection
    var history: [AgentConversationExchange]
    var preparationMilliseconds: Int
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
        var frameGroups: [[Data]] = []
        var imageCount = 0
        let videoAttachments = attachments.filter { $0.kind == .video }
        let videoCount = videoAttachments.count
        var failedVideoCount = 0
        for attachment in attachments {
            switch attachment.kind {
            case .none, .video:
                continue
            case .image:
                guard let url = MediaStore.url(at: attachment.path) else {
                    continue
                }
                if let data = try? Data(contentsOf: url) {
                    frameGroups.append([data])
                    imageCount += 1
                }
            }
        }
        var videos: [AgentVideoInput] = []
        if let directVideoCapability, !videoAttachments.isEmpty {
            for attachment in videoAttachments {
                guard let url = MediaStore.url(at: attachment.path),
                      let input = await DirectVideoPreparer.input(
                          for: url,
                          capability: directVideoCapability
                      )
                else {
                    videos = []
                    break
                }
                videos.append(input)
            }
        }
        if videos.count != videoCount {
            failedVideoCount = videoCount
            videos = []
        }
        let mode: AgentMediaMode = if !videos.isEmpty {
            .directVideo
        } else if imageCount > 0 {
            .images
        } else {
            .text
        }
        return PreparedConversationMedia(
            attachments: attachments,
            frames: balancedFrames(from: frameGroups, limit: frameLimit),
            videos: videos,
            imageCount: imageCount,
            videoCount: videoCount,
            failedVideoCount: failedVideoCount,
            mode: mode
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

    private nonisolated func balancedFrames(
        from groups: [[Data]],
        limit: Int
    ) -> [Data] {
        guard limit > 0 else { return [] }
        var result: [Data] = []
        var index = 0
        while result.count < limit {
            var appended = false
            for group in groups where index < group.count {
                result.append(group[index])
                appended = true
                if result.count == limit {
                    return result
                }
            }
            guard appended else { break }
            index += 1
        }
        return result
    }
}
