import Foundation

enum AgentStepRetryPolicy {
    static let maximumRetryCount = 3

    static func delay(forRetry retry: Int) -> TimeInterval {
        pow(2, Double(max(0, retry - 1)))
    }
}
