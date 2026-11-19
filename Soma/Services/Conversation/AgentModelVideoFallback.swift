import Foundation

struct AgentModelVideoFallback: Codable, Equatable, Sendable {
    let videoID: String
    let frameIDs: [String]
    let timestampsSeconds: [Double]
    let durationSeconds: Double
}
