import Foundation
import SwiftData

/// Agent projection stays mounted at the app root. Its supporting database
/// counts therefore run on a ModelActor instead of competing with Tab taps on
/// the MainActor.
@ModelActor
actor AgentProjectionOperationCountLoader {
    func load(jobIDs: [UUID]) throws -> [UUID: Int] {
        let spanKind = PersistentAgentEventKind.span.rawValue
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(jobIDs.count)
        for jobID in jobIDs {
            try Task.checkCancellation()
            let descriptor = FetchDescriptor<PersistentAgentEvent>(
                predicate: #Predicate {
                    $0.jobID == jobID && $0.kindRaw == spanKind
                }
            )
            counts[jobID] = try modelContext.fetchCount(descriptor)
        }
        return counts
    }
}
