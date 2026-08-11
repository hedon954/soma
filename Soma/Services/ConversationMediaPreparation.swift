import Foundation

struct PreparedAgentHistory {
    var projection: ConversationContextProjection
    var history: [AgentConversationExchange]
    var preparationMilliseconds: Int
}

extension ConversationProcessingService {
    func prepareStoredMedia(
        _ attachments: [MediaAttachmentReference],
        frameLimit: Int,
        directVideoCapability: DirectVideoCapability? = nil
    ) async -> PreparedConversationMedia {
        guard frameLimit > 0 else {
            return PreparedConversationMedia(
                attachments: attachments,
                frames: [],
                imageCount: attachments.count { $0.kind == .image },
                videoCount: attachments.count { $0.kind == .video },
                failedVideoCount: 0,
                mode: attachments.isEmpty ? .text : .images
            )
        }
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
        if videos.count != videoAttachments.count {
            videos = []
            for attachment in videoAttachments {
                guard let url = MediaStore.url(at: attachment.path) else {
                    failedVideoCount += 1
                    continue
                }
                let frames = await VideoFrameCache.frames(for: url)
                frameGroups.append(frames)
                if frames.isEmpty {
                    failedVideoCount += 1
                }
            }
        }
        let mode: AgentMediaMode = if !videos.isEmpty {
            .directVideo
        } else if videoCount > 0 {
            .keyframes
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
        return ModelCapability.directVideoCapability(
            provider: route.provider,
            model: route.model
        )
    }

    private func balancedFrames(
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
