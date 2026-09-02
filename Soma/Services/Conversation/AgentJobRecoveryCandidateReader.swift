import Foundation
import SwiftData

/// 前台恢复先在独立读取 Context 中只取 FIFO 候选的稳定 ID，避免把后台
/// Context 的 `@Model` 带回 UI actor。真正的状态转换仍由 MainActor Context 重取。
@ModelActor
actor AgentJobRecoveryCandidateReader {
    func firstCandidateID(dataSpace: DataSpace) throws -> UUID? {
        let dataSpaceRaw = dataSpace.rawValue
        let succeeded = AgentJobState.succeeded.rawValue
        let failed = AgentJobState.failed.rawValue
        let cancelled = AgentJobState.cancelled.rawValue
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw
                    && $0.stateRaw != succeeded
                    && $0.stateRaw != failed
                    && $0.stateRaw != cancelled
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.id
    }
}
