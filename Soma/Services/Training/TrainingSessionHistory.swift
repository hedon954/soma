import Foundation
import Observation
import SwiftData

/// 训练根页持有的已结束 Session 分页。只查询未缓存身份，避免偏移在新增后漏项。
@MainActor
@Observable
final class TrainingSessionHistory {
    static let pageSize = 14
    private(set) var sessions: [WorkoutSession] = []
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private let fetchPage: (ModelContext, FetchDescriptor<WorkoutSession>) throws -> [WorkoutSession]
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private(set) var pageFetchCount = 0

    init(
        fetchPage: @escaping (ModelContext, FetchDescriptor<WorkoutSession>) throws -> [WorkoutSession] = {
            try $0.fetch($1)
        }
    ) {
        self.fetchPage = fetchPage
    }

    func loadIfNeeded(in context: ModelContext) {
        bind(to: context)
        guard !didLoad else { return }
        loadNextPage(in: context)
    }

    func loadNextPage(in context: ModelContext) {
        bind(to: context)
        guard hasMore else { return }
        let cachedIDs = sessions.map(\.id)
        let completed = WorkoutSessionStatus.completed.rawValue
        let abandoned = WorkoutSessionStatus.abandoned.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                ($0.statusRaw == completed || $0.statusRaw == abandoned)
                    && !cachedIDs.contains($0.id)
            },
            sortBy: [
                SortDescriptor(\.startedAt, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = Self.pageSize
        do {
            pageFetchCount += 1
            let page = try fetchPage(context, descriptor)
            sessions.append(contentsOf: page)
            sortSessions()
            hasMore = page.count == Self.pageSize
            didLoad = true
            errorMessage = nil
        } catch {
            errorMessage = AppErrorMessage.message(for: error, operation: .load)
        }
    }

    func applySave(_ notification: Notification, in context: ModelContext) {
        bind(to: context)
        guard didLoad,
              let source = notification.object as? ModelContext,
              source.container === context.container
        else { return }
        let info = notification.userInfo ?? [:]
        if info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil {
            reset()
            loadIfNeeded(in: context)
            return
        }
        let deleted = Set(identifiers(.deletedIdentifiers, in: info))
        let changed = Set(identifiers(.insertedIdentifiers, in: info) + identifiers(.updatedIdentifiers, in: info))
            .subtracting(deleted)
        guard !deleted.isEmpty || !changed.isEmpty else { return }
        sessions.removeAll { deleted.contains($0.persistentModelID) }
        for identifier in changed {
            guard let session = context.model(for: identifier) as? WorkoutSession else { continue }
            if session.status == .completed || session.status == .abandoned {
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index] = session
                } else {
                    sessions.append(session)
                }
            } else {
                sessions.removeAll { $0.id == session.id }
            }
        }
        sortSessions()
    }

    private func identifiers(
        _ key: ModelContext.NotificationKey,
        in info: [AnyHashable: Any]
    ) -> [PersistentIdentifier] {
        let values = (info[key.rawValue] as? [PersistentIdentifier])
            ?? Array(info[key.rawValue] as? Set<PersistentIdentifier> ?? [])
        return values.filter { $0.entityName == String(describing: WorkoutSession.self) }
    }

    private func sortSessions() {
        sessions.sort { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private func bind(to context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        reset()
    }

    private func reset() {
        sessions = []
        hasMore = true
        didLoad = false
        errorMessage = nil
        pageFetchCount = 0
    }
}
