import Foundation
import Observation
import SwiftData
import UIKit

enum DataManagementActivity: Equatable {
    case exporting
    case backingUp
    case restoring
    case clearing

    var title: String {
        switch self {
        case .exporting: "正在导出"
        case .backingUp: "正在备份"
        case .restoring: "正在恢复"
        case .clearing: "正在清除"
        }
    }
}

@MainActor
@Observable
final class DataManagementCoordinator {
    static let backupKeychainAccount = "data.backup.derivedKey"

    private enum DefaultsKey {
        static let bookmark = "data.backup.destinationBookmark"
        static let destinationName = "data.backup.destinationName"
        static let salt = "data.backup.salt"
        static let iterations = "data.backup.iterations"
        static let lastBackupAt = "data.backup.lastSuccessAt"
        static let lastError = "data.backup.lastError"
        static let contentFingerprint = "data.backup.contentFingerprint"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let backupBackgroundLease: BackgroundExecutionLease
    @ObservationIgnored private var automaticBackupTask: Task<Void, Never>?
    private(set) var activity: DataManagementActivity?
    private(set) var lastBackupAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var backupDestinationName: String?
    private(set) var lastExportResult: PortableExportResult?

    init(
        defaults: UserDefaults = .standard,
        backupBackgroundLease: BackgroundExecutionLease? = nil
    ) {
        self.defaults = defaults
        self.backupBackgroundLease = backupBackgroundLease
            ?? UIKitBackgroundExecutionLease()
        lastBackupAt = defaults.object(forKey: DefaultsKey.lastBackupAt) as? Date
        lastErrorMessage = defaults.string(forKey: DefaultsKey.lastError)
        backupDestinationName = defaults.string(forKey: DefaultsKey.destinationName)
    }

    var isBackupConfigured: Bool {
        defaults.data(forKey: DefaultsKey.bookmark) != nil
            && defaults.data(forKey: DefaultsKey.salt) != nil
            && KeychainStore.readData(Self.backupKeychainAccount) != nil
    }

    var isWorking: Bool {
        activity != nil
    }

    func exportRecords(
        to destination: URL,
        personalContainer: ModelContainer
    ) async throws -> PortableExportResult {
        guard activity == nil else { throw DataArchiveError.backupAlreadyRunning }
        activity = .exporting
        defer { activity = nil }
        lastExportResult = nil

        let snapshot = try await captureSnapshot(from: personalContainer)
        let payload = PortableExportPayload(snapshot: snapshot)
        do {
            let result = try await withSecurityScopedAccess(to: destination) {
                try await runDetached(priority: .userInitiated) {
                    try DataExportService.export(payload, to: destination)
                }
            }
            lastExportResult = result
            return result
        } catch {
            throw userFacing(error, fallback: "导出失败，请检查目标文件夹后重试。")
        }
    }

    func configureBackup(
        destination: URL,
        password: String,
        personalContainer: ModelContainer
    ) async throws -> DataBackupWriteResult {
        guard activity == nil else { throw DataArchiveError.backupAlreadyRunning }
        activity = .backingUp
        defer { activity = nil }

        let salt = try DataBackupCrypto.randomSalt()
        let iterations = DataBackupCrypto.defaultIterations
        let keyData = try await runDetached(priority: .userInitiated) {
            try DataBackupCrypto.deriveKeyData(
                password: password,
                salt: salt,
                iterations: iterations
            )
        }
        let credential = DataBackupCredential(
            salt: salt,
            iterations: iterations,
            keyData: keyData
        )
        let snapshot = try await captureSnapshot(from: personalContainer)

        do {
            let configured = try await withSecurityScopedAccess(to: destination) {
                let bookmark = try destination.bookmarkData()
                let result = try await runDetached(priority: .userInitiated) {
                    try DataBackupService.write(
                        snapshot: snapshot,
                        to: destination,
                        credential: credential
                    )
                }
                return (result, bookmark)
            }
            defaults.set(configured.1, forKey: DefaultsKey.bookmark)
            defaults.set(destination.lastPathComponent, forKey: DefaultsKey.destinationName)
            defaults.set(salt, forKey: DefaultsKey.salt)
            defaults.set(iterations, forKey: DefaultsKey.iterations)
            KeychainStore.saveData(keyData, for: Self.backupKeychainAccount)
            recordBackupSuccess(at: configured.0.completedAt)
            try defaults.set(
                snapshot.contentFingerprint(),
                forKey: DefaultsKey.contentFingerprint
            )
            backupDestinationName = destination.lastPathComponent
            return configured.0
        } catch {
            recordBackupFailure(error)
            throw userFacing(error, fallback: "无法在所选文件夹创建备份。")
        }
    }

    func backupNow(
        personalContainer: ModelContainer,
        allowBusySkip: Bool = false,
        skipIfUnchanged: Bool = false
    ) async throws -> DataBackupWriteResult? {
        if activity != nil {
            if allowBusySkip {
                return nil
            }
            throw DataArchiveError.backupAlreadyRunning
        }
        guard let credential = configuredCredential() else {
            throw DataArchiveError.backupNotConfigured
        }
        activity = .backingUp
        defer { activity = nil }
        try Task.checkCancellation()

        let destination: URL
        let bookmarkIsStale: Bool
        do {
            (destination, bookmarkIsStale) = try resolveBackupDestination()
        } catch {
            recordBackupFailure(error)
            throw DataArchiveError.destinationUnavailable
        }
        let snapshot = try await captureSnapshot(from: personalContainer)
        try Task.checkCancellation()
        let fingerprint = try snapshot.contentFingerprint()
        if skipIfUnchanged,
           fingerprint == defaults.string(forKey: DefaultsKey.contentFingerprint)
        {
            return nil
        }
        do {
            let backedUp = try await withSecurityScopedAccess(to: destination) {
                let refreshedBookmark = bookmarkIsStale
                    ? try destination.bookmarkData()
                    : nil
                let result = try await runDetached(priority: .utility) {
                    try Task.checkCancellation()
                    return try DataBackupService.write(
                        snapshot: snapshot,
                        to: destination,
                        credential: credential
                    )
                }
                return (result, refreshedBookmark)
            }
            if let refreshedBookmark = backedUp.1 {
                defaults.set(refreshedBookmark, forKey: DefaultsKey.bookmark)
            }
            recordBackupSuccess(at: backedUp.0.completedAt)
            defaults.set(fingerprint, forKey: DefaultsKey.contentFingerprint)
            return backedUp.0
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            recordBackupFailure(error)
            throw userFacing(error, fallback: "自动备份未完成，上一份备份仍然保留。")
        }
    }

    func backupWhenEnteringBackground(
        personalContainer: ModelContainer
    ) {
        guard isBackupConfigured, automaticBackupTask == nil else { return }
        backupBackgroundLease.begin { [weak self] in
            self?.automaticBackupTask?.cancel()
            self?.automaticBackupTask = nil
        }
        automaticBackupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                backupBackgroundLease.end()
                automaticBackupTask = nil
            }
            _ = try? await backupNow(
                personalContainer: personalContainer,
                allowBusySkip: true,
                skipIfUnchanged: true
            )
        }
    }

    /// 回到前台优先保证界面可交互。取消只中止尚未完成的自动备份，上一份
    /// 成功备份不会被删除；下一次进入后台会重新尝试。
    func cancelAutomaticBackupForForeground() {
        guard let automaticBackupTask else { return }
        AppPerformance.event(.backupCancellation, detail: "reason=scene_active")
        automaticBackupTask.cancel()
    }

    func restore(
        from selectedDirectory: URL,
        password: String,
        dataSpace: DataSpaceController
    ) async throws {
        guard activity == nil else { throw DataArchiveError.backupAlreadyRunning }
        activity = .restoring
        defer { activity = nil }

        let prepared: PreparedDataRestore
        do {
            prepared = try await withSecurityScopedAccess(to: selectedDirectory) {
                try await runDetached(priority: .userInitiated) {
                    try DataBackupService.prepareRestore(
                        from: selectedDirectory,
                        password: password
                    )
                }
            }
        } catch {
            throw userFacing(error, fallback: "无法读取这份备份，当前数据没有改变。")
        }

        let personalContainer: ModelContainer = dataSpace.personalContainer
        let demoContainer: ModelContainer = dataSpace.demoContainer
        let personalContext = personalContainer.mainContext
        let oldMedia: Set<String>
        let demoMedia: Set<String>
        do {
            let containers = (
                personal: personalContainer,
                demo: demoContainer
            )
            let references = try await runDetached(priority: .utility) {
                try (
                    MediaReferenceStore.referencedPaths(in: containers.personal),
                    MediaReferenceStore.referencedPaths(in: containers.demo)
                )
            }
            oldMedia = references.0
            demoMedia = references.1
            try prepared.snapshot.replace(
                in: personalContext,
                mediaPathMapping: prepared.mediaPathMapping
            )
            try SomaDataMigration.migrateIfNeeded(
                container: personalContainer,
                dataSpace: .personal
            )
        } catch {
            for createdMediaPath in prepared.createdMediaPaths {
                MediaStore.removeStoredFile(at: createdMediaPath)
            }
            throw userFacing(error, fallback: "恢复失败，当前数据没有改变。")
        }
        let restoredMedia = Set(prepared.mediaPathMapping.values)
        _ = PersonalDataStore.reclaimMedia(
            oldMedia.union(MediaStore.allStoredPaths()),
            excluding: demoMedia.union(restoredMedia)
        )
    }

    func clearPersonalData(
        dataSpace: DataSpaceController
    ) async throws -> PersonalDataClearResult {
        guard activity == nil else { throw DataArchiveError.backupAlreadyRunning }
        activity = .clearing
        defer { activity = nil }
        await RemoteAgentStatus().revokeAndDisable()
        let result = try PersonalDataStore.clear(
            personalContext: dataSpace.personalContainer.mainContext,
            demoContext: dataSpace.demoContainer.mainContext
        )
        disconnectBackup()
        return result
    }

    func disconnectBackup() {
        defaults.removeObject(forKey: DefaultsKey.bookmark)
        defaults.removeObject(forKey: DefaultsKey.destinationName)
        defaults.removeObject(forKey: DefaultsKey.salt)
        defaults.removeObject(forKey: DefaultsKey.iterations)
        defaults.removeObject(forKey: DefaultsKey.lastBackupAt)
        defaults.removeObject(forKey: DefaultsKey.lastError)
        defaults.removeObject(forKey: DefaultsKey.contentFingerprint)
        KeychainStore.delete(Self.backupKeychainAccount)
        lastBackupAt = nil
        lastErrorMessage = nil
        backupDestinationName = nil
    }

    private func configuredCredential() -> DataBackupCredential? {
        guard let salt = defaults.data(forKey: DefaultsKey.salt),
              let keyData = KeychainStore.readData(Self.backupKeychainAccount)
        else {
            return nil
        }
        let iterations = defaults.integer(forKey: DefaultsKey.iterations)
        return DataBackupCredential(
            salt: salt,
            iterations: iterations > 0 ? iterations : DataBackupCrypto.defaultIterations,
            keyData: keyData
        )
    }

    private func captureSnapshot(
        from container: ModelContainer
    ) async throws -> PersonalDataSnapshot {
        try await runDetached(priority: .userInitiated) {
            try Task.checkCancellation()
            let loader = PersonalDataSnapshotLoader(modelContainer: container)
            return try await loader.capture()
        }
    }

    private func runDetached<T: Sendable>(
        priority: TaskPriority,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: priority) {
            try await operation()
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func resolveBackupDestination() throws -> (URL, Bool) {
        guard let bookmark = defaults.data(forKey: DefaultsKey.bookmark) else {
            throw DataArchiveError.backupNotConfigured
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    private func recordBackupSuccess(at date: Date) {
        lastBackupAt = date
        lastErrorMessage = nil
        defaults.set(date, forKey: DefaultsKey.lastBackupAt)
        defaults.removeObject(forKey: DefaultsKey.lastError)
    }

    private func recordBackupFailure(_ error: Error) {
        let message = userFacing(
            error,
            fallback: "备份未完成，上一份备份仍然保留。"
        ).localizedDescription
        lastErrorMessage = message
        defaults.set(message, forKey: DefaultsKey.lastError)
    }

    private func userFacing(_ error: Error, fallback: String) -> Error {
        if error is DataArchiveError {
            return error
        }
        return DataManagementDisplayError(message: fallback)
    }

    private func withSecurityScopedAccess<T: Sendable>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
    }
}

private struct DataManagementDisplayError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}
