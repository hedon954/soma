import Foundation
import Observation
import SwiftData

/// 抽屉外持有分页缓存；仅加载未缓存身份，避免 offset 在会话更新/删除后跳行。
@MainActor
@Observable
final class ConversationSessionHistory {
    static let pageSize = 14
    private(set) var sessions: [ConversationSession] = []
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private let fetchPage: (ModelContext, FetchDescriptor<ConversationSession>) throws -> [ConversationSession]
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private(set) var pageFetchCount = 0

    init(fetchPage: @escaping (ModelContext, FetchDescriptor<ConversationSession>) throws -> [ConversationSession] = { try $0.fetch($1) }) {
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
        var descriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { !cachedIDs.contains($0.id) },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.id)]
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
            guard let session = context.model(for: identifier) as? ConversationSession else { continue }
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
        }
        sortSessions()
    }

    private func identifiers(_ key: ModelContext.NotificationKey, in info: [AnyHashable: Any]) -> [PersistentIdentifier] {
        let values = (info[key.rawValue] as? [PersistentIdentifier])
            ?? Array(info[key.rawValue] as? Set<PersistentIdentifier> ?? [])
        return values.filter { $0.entityName == String(describing: ConversationSession.self) }
    }

    private func sortSessions() {
        sessions.sort {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id.uuidString < $1.id.uuidString
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
