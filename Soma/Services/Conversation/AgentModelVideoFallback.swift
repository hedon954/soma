import Foundation

struct AgentModelVideoFallback: Codable, Equatable, Sendable {
    let videoID: String
    let frameIDs: [String]
    let timestampsSeconds: [Double]
    let durationSeconds: Double
}

enum AgentModelVideoFallbackPreparation {
    static func adding(to input: PreparedAgentModelInput) async throws -> PreparedAgentModelInput {
        let videos: [(String, AgentVideoInput)] = input.media.compactMap { payload in
            guard case let .video(id, video) = payload else { return nil }
            return (id, video)
        }
        guard !videos.isEmpty else { return input }
        let frames = try await VideoFrameFallbackPreparer.prepare(videos.map(\.1))
        var result = input
        var manifests: [AgentModelVideoFallback] = []
        for ((id, _), set) in zip(videos, frames) {
            let frameIDs = set.frames.indices.map { "fallback-\(id)-\($0)" }
            for (frameID, data) in zip(frameIDs, set.frames) {
                result.media.append(.image(id: frameID, data: data))
            }
            manifests.append(AgentModelVideoFallback(
                videoID: id, frameIDs: frameIDs, timestampsSeconds: set.timestampsSeconds,
                durationSeconds: set.durationSeconds
            ))
        }
        result.envelope.videoFallbacks = manifests
        return result
    }
}
