import Foundation
import Observation
import SwiftData

private struct PreparedConversationMedia {
    var attachments: [MediaAttachmentReference]
    var frames: [Data]
    var imageCount: Int
    var videoCount: Int

    var hasVideo: Bool {
        videoCount > 0
    }

    var primaryKind: MediaKind {
        attachments.first?.kind ?? .none
    }

    var primaryPath: String? {
        attachments.first?.path
    }

    var displaySummary: String {
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "发送了媒体" : "发送了" + parts.joined(separator: "和")
    }
}

struct ConversationProcessingContext {
    var contextSummary: String
    var session: ConversationSession
    var dataSpace: DataSpace
    var gyms: [GymProfile]
    var equipment: [GymEquipment]
    var ai: AIService
    var modelContext: ModelContext
}

@MainActor
@Observable
final class ConversationProcessingService {
    private(set) var isProcessing = false
    private(set) var dataSpace: DataSpace?
    private(set) var liveAssistantText = ""
    private(set) var liveAgentActivity: String?
    private(set) var liveEventRevision = 0

    @ObservationIgnored
    private var processingTask: Task<Void, Never>?

    @discardableResult
    func submit(
        text: String,
        attachments: [PendingAttachment],
        context: ConversationProcessingContext,
        includeLocation: Bool,
        locationService: LocationContextService
    ) -> Bool {
        guard beginProcessing(dataSpace: context.dataSpace, ai: context.ai) else {
            return false
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            await processNewTurn(
                text: text,
                attachments: attachments,
                context: context,
                includeLocation: includeLocation,
                locationService: locationService
            )
        }
        return true
    }

    @discardableResult
    func retry(
        userMessage: CoachMessage,
        context: ConversationProcessingContext
    ) -> Bool {
        guard !userMessage.isFromCoach,
              userMessage.turnID != nil,
              beginProcessing(dataSpace: context.dataSpace, ai: context.ai)
        else {
            return false
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            let media = await prepareStoredMedia(userMessage.mediaAttachments)
            await runAttempt(
                userMessage: userMessage,
                media: media,
                context: context
            )
        }
        return true
    }

    private func beginProcessing(dataSpace: DataSpace, ai: AIService) -> Bool {
        guard !isProcessing else { return false }
        isProcessing = true
        self.dataSpace = dataSpace
        liveAssistantText = ""
        liveAgentActivity = ai.isRemoteEnabled
            ? "正在启动 Agent…"
            : "正在理解并整理…"
        return true
    }

    private func processNewTurn(
        text: String,
        attachments: [PendingAttachment],
        context: ConversationProcessingContext,
        includeLocation: Bool,
        locationService: LocationContextService
    ) async {
        let media = await prepareMedia(attachments)
        let displayText = text.isEmpty ? media.displaySummary : text
        let userMessageDate = Date.now
        let turnID = UUID()
        context.session.recordUserMessage(displayText, at: userMessageDate)
        let userMessage = CoachMessage(
            date: userMessageDate,
            sessionID: context.session.id,
            isFromCoach: false,
            text: text,
            mediaKind: media.primaryKind,
            mediaPath: media.primaryPath,
            mediaAttachments: media.attachments,
            turnID: turnID
        )
        context.modelContext.insert(userMessage)
        try? context.modelContext.save()

        if includeLocation {
            liveAgentActivity = "正在获取本次位置…"
            userMessage.location = await locationService.requestSnapshot()
            try? context.modelContext.save()
        }

        await runAttempt(
            userMessage: userMessage,
            media: media,
            context: context
        )
    }

    private func runAttempt(
        userMessage: CoachMessage,
        media: PreparedConversationMedia,
        context: ConversationProcessingContext
    ) async {
        guard let turnID = userMessage.turnID else {
            finishProcessing()
            return
        }
        let displayText = userMessage.text.isEmpty
            ? media.displaySummary
            : userMessage.text
        let attemptNumber = nextAttemptNumber(
            for: turnID,
            in: context.modelContext
        )
        let resolution = GymLocationResolver.resolve(
            text: userMessage.text,
            snapshot: userMessage.location,
            gyms: context.gyms
        )
        userMessage.effectiveGymID = resolution.gymID
        let effectiveGym = resolution.gymID.flatMap { id in
            context.gyms.first { $0.id == id }
        }
        let persistentContext = context.contextSummary + turnContext(
            location: userMessage.location,
            gym: effectiveGym,
            source: resolution.source
        )
        let weatherGuidance: String? = if let location = userMessage.location {
            await WeatherContextProvider.transientGuidance(
                for: location,
                text: userMessage.text
            )
        } else {
            nil
        }
        let agentContext = [persistentContext, weatherGuidance]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var performedRecordType: ConversationIntent?
        var activeTrace: AgentTrace?
        let responseMessage = CoachMessage(
            sessionID: context.session.id,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: attemptNumber
        )
        context.modelContext.insert(responseMessage)
        try? context.modelContext.save()

        do {
            let reply: String
            if context.ai.isRemoteEnabled {
                let provider = context.ai.provider
                let trace = AgentTrace(
                    provider: provider.displayName,
                    model: context.ai.model(for: provider),
                    endpoint: provider.endpoint(
                        baseURL: context.ai.baseURL(for: provider),
                        path: "chat/completions"
                    )?.absoluteString ?? context.ai.baseURL(for: provider),
                    dataSpaceRaw: context.dataSpace.rawValue,
                    userInput: displayText,
                    contextSnapshot: persistentContext,
                    mediaKind: media.primaryKind,
                    imageCount: media.frames.count,
                    imageAttachmentCount: media.imageCount,
                    videoAttachmentCount: media.videoCount,
                    turnID: turnID,
                    attemptNumber: attemptNumber
                )
                activeTrace = trace
                responseMessage.agentTraceID = trace.id
                context.modelContext.insert(trace)
                try? context.modelContext.save()

                let outcome = try await context.ai.runAgent(
                    text: userMessage.text,
                    images: media.frames,
                    hasVideo: media.hasVideo,
                    imageAttachmentCount: media.imageCount,
                    videoAttachmentCount: media.videoCount,
                    context: agentContext,
                    trace: { [weak self] event in
                        self?.applyLiveAgentEvent(event)
                        trace.apply(event)
                        responseMessage.applyAgentEvent(event)
                        switch event {
                        case let .assistantTextDelta(_, delta):
                            responseMessage.text += delta
                        case .assistantTextCompleted, .span:
                            break
                        case .completed:
                            responseMessage.agentStatus = .succeeded
                        case let .failed(_, cancelled, _):
                            responseMessage.agentStatus = cancelled ? .cancelled : .failed
                        }
                        if case .assistantTextDelta = event {
                        } else {
                            try? context.modelContext.save()
                        }
                    }
                ) { call in
                    let result = AgentMutationStore.execute(
                        call,
                        turnID: turnID,
                        in: context.modelContext
                    ) {
                        ConversationRecorder.executeAgentTool(
                            call,
                            sourceText: userMessage.text,
                            sourceDate: userMessage.date,
                            sourceSessionID: context.session.id,
                            sourceTurnID: turnID,
                            mediaKind: media.primaryKind,
                            mediaPath: media.primaryPath,
                            mediaAttachments: media.attachments,
                            preferredGymID: resolution.gymID,
                            in: context.modelContext
                        )
                    }
                    if let recordType = result.recordType {
                        performedRecordType = recordType
                    }
                    return result
                }
                reply = outcome.finalAnswer
                performedRecordType = outcome.primaryRecordType ?? performedRecordType
            } else {
                let result = try await context.ai.interpretConversation(
                    text: userMessage.text,
                    images: media.frames,
                    hasVideo: media.hasVideo,
                    context: agentContext,
                    allowDemoFallback: context.dataSpace == .demo
                )
                reply = ConversationRecorder.apply(
                    result,
                    sourceText: userMessage.text,
                    sourceDate: userMessage.date,
                    sourceSessionID: context.session.id,
                    sourceTurnID: turnID,
                    mediaKind: media.primaryKind,
                    mediaPath: media.primaryPath,
                    mediaAttachments: media.attachments,
                    gyms: context.gyms,
                    equipment: context.equipment,
                    in: context.modelContext
                )
                performedRecordType = result.intent
            }

            responseMessage.text = reply
            responseMessage.recordType = performedRecordType
            responseMessage.agentStatus = .succeeded
        } catch {
            let reason = error.localizedDescription
            let recovery = if performedRecordType != nil {
                "\n\nAgent 已完成的本地记录仍然保留，但生成最终回复时中断。"
            } else if !media.attachments.isEmpty {
                "\n\n附件已保存在本机对话中，但这次没有自动生成统计记录。请检查模型的多模态能力后重试。"
            } else {
                ""
            }
            let failureText = "这次没有处理成功：\(reason)。\(recovery)"
            responseMessage.text = failureText
            responseMessage.agentStatus = .failed
            if let activeTrace, activeTrace.status == .running {
                activeTrace.apply(.failed(
                    message: reason,
                    cancelled: false,
                    at: .now
                ))
            }
            if !responseMessage.agentTurnItems.contains(where: { $0.kind == .error }) {
                responseMessage.applyAgentEvent(.failed(
                    message: reason,
                    cancelled: false,
                    at: .now
                ))
            }
        }

        context.session.touch(at: .now)
        try? context.modelContext.save()
        finishProcessing()
    }

    private func nextAttemptNumber(
        for turnID: UUID,
        in context: ModelContext
    ) -> Int {
        let messages = (
            try? context.fetch(FetchDescriptor<CoachMessage>())
        ) ?? []
        return messages
            .filter { $0.isFromCoach && $0.turnID == turnID }
            .map(\.attemptNumber)
            .max()
            .map { $0 + 1 }
            ?? 1
    }

    private func turnContext(
        location: LocationSnapshot?,
        gym: GymProfile?,
        source: GymContextSource
    ) -> String {
        var parts: [String] = []
        if let location {
            parts.append("本次语义位置：\(location.displayName)。不要向用户或远程服务输出原始坐标。")
        }
        if let gym {
            let note = source == .nearby
                ? "由本地位置唯一匹配，本次使用但不改变全局当前健身房"
                : "本次有效场馆"
            parts.append("\(note)：\(gym.name)。")
        }
        return parts.isEmpty ? "" : "\n本次上下文：\n" + parts.joined(separator: "\n")
    }

    private func finishProcessing() {
        liveAssistantText = ""
        liveAgentActivity = nil
        isProcessing = false
        dataSpace = nil
        processingTask = nil
    }

    private func prepareMedia(
        _ attachments: [PendingAttachment]
    ) async -> PreparedConversationMedia {
        var references: [MediaAttachmentReference] = []
        var frameGroups: [[Data]] = []
        var imageCount = 0
        var videoCount = 0

        for attachment in attachments {
            switch attachment.kind {
            case .none:
                continue
            case .image:
                guard
                    let data = attachment.imageData,
                    let path = try? MediaStore.saveImage(data)
                else {
                    continue
                }
                references.append(MediaAttachmentReference(kind: .image, path: path))
                frameGroups.append([data])
                imageCount += 1
            case .video:
                guard
                    let url = attachment.videoURL,
                    let path = try? MediaStore.saveVideo(from: url)
                else {
                    continue
                }
                references.append(MediaAttachmentReference(kind: .video, path: path))
                await frameGroups.append(VideoFrameExtractor.frames(from: url))
                videoCount += 1
            }
        }

        return PreparedConversationMedia(
            attachments: references,
            frames: Self.balancedFrames(from: frameGroups, limit: 12),
            imageCount: imageCount,
            videoCount: videoCount
        )
    }

    private func prepareStoredMedia(
        _ attachments: [MediaAttachmentReference]
    ) async -> PreparedConversationMedia {
        var frameGroups: [[Data]] = []
        var imageCount = 0
        var videoCount = 0
        for attachment in attachments {
            guard let url = MediaStore.url(at: attachment.path) else { continue }
            switch attachment.kind {
            case .none:
                continue
            case .image:
                if let data = try? Data(contentsOf: url) {
                    frameGroups.append([data])
                    imageCount += 1
                }
            case .video:
                await frameGroups.append(VideoFrameExtractor.frames(from: url))
                videoCount += 1
            }
        }
        return PreparedConversationMedia(
            attachments: attachments,
            frames: Self.balancedFrames(from: frameGroups, limit: 12),
            imageCount: imageCount,
            videoCount: videoCount
        )
    }

    private static func balancedFrames(
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

    private func applyLiveAgentEvent(_ event: AgentTraceEvent) {
        liveEventRevision += 1
        switch event {
        case let .assistantTextDelta(_, delta):
            liveAssistantText += delta
            liveAgentActivity = "正在生成回复…"
        case .assistantTextCompleted:
            liveAgentActivity = nil
        case let .span(span):
            guard span.status == .running else { return }
            switch span.kind {
            case .model:
                liveAgentActivity = "模型正在响应…"
            case .skill:
                liveAgentActivity = "正在加载 Skill：\(span.title)"
            case .tool:
                liveAgentActivity = "正在执行：\(span.title)"
            case .output:
                liveAgentActivity = "正在整理结果…"
            }
        case .completed, .failed:
            liveAgentActivity = nil
        }
    }
}
