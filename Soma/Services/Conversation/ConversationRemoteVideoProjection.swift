import Foundation

@MainActor
extension ConversationProcessingService {
    func projectRemoteVideoFallback(
        _ event: RemoteAgentEvent,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext
    ) {
        let count = event.payload["frameCount"]?.intValue ?? 0
        projectRemoteSpan(
            AgentTraceSpan(
                sequence: event.sequence, kind: .model,
                title: (8 ... 24).contains(count) ? "改用 \(count) 张画面分析" : "改用视频画面分析",
                status: .succeeded, startedAt: event.createdAt, endedAt: event.createdAt,
                metadata: remoteModelSpanMetadata(event)
            ),
            job: job, responseMessage: responseMessage, trace: trace, context: context
        )
    }
}
