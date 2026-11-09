import Foundation
import HealthKit

protocol BodyMassReading: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func pull(anchorData: Data?) async throws -> BodyMassSyncDelta
    func pullBodyFat(anchorData: Data?) async throws -> BodyFatSyncDelta
    func startObserving(onChange: @escaping @Sendable () -> Void) async
    func stopObserving() async
}

actor HealthKitBodyMassReader: BodyMassReading {
    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var store: HKHealthStore?
    private var bodyMassObserver: HKObserverQuery?
    private var bodyFatObserver: HKObserverQuery?
    private var backgroundEnabledTypes: Set<HKQuantityType> = []

    static let bodyMassType = HKQuantityType(.bodyMass)
    static let bodyFatType = HKQuantityType(.bodyFatPercentage)

    static let readTypes: Set<HKObjectType> = [
        bodyMassType,
        bodyFatType
    ]

    private func healthStore() -> HKHealthStore {
        if let store {
            return store
        }
        let result = HKHealthStore()
        store = result
        return result
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw BodyMassReadError.unavailable }
        try await healthStore().requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func pull(anchorData: Data?) async throws -> BodyMassSyncDelta {
        guard isAvailable else { throw BodyMassReadError.unavailable }
        let healthStore = healthStore()
        let anchor = try decodeAnchor(anchorData)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: Self.bodyMassType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                // 读权限被拒与「暂无样本」在 HealthKit 中通常都表现为空结果且无 error；
                // 空 upsert/空 deleted 不得被解读为清空本地导入。
                let upserts = (samples ?? []).compactMap { sample -> BodyMassSampleImport? in
                    guard let quantity = sample as? HKQuantitySample else { return nil }
                    let kg = quantity.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    guard kg.isFinite, kg > 0 else { return nil }
                    let source = quantity.sourceRevision.source
                    return BodyMassSampleImport(
                        sampleUUID: quantity.uuid,
                        date: quantity.startDate,
                        weightKilograms: kg,
                        sourceName: source.name,
                        sourceBundleIdentifier: source.bundleIdentifier
                    )
                }
                let deletedIDs = (deleted ?? []).map(\.uuid)
                continuation.resume(
                    returning: BodyMassSyncDelta(
                        upserts: upserts,
                        deletedSampleUUIDs: deletedIDs,
                        newAnchorData: Self.encodeAnchor(newAnchor)
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    func pullBodyFat(anchorData: Data?) async throws -> BodyFatSyncDelta {
        guard isAvailable else { throw BodyMassReadError.unavailable }
        let healthStore = healthStore()
        let anchor = try decodeAnchor(anchorData)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: Self.bodyFatType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let upserts = (samples ?? []).compactMap { sample -> BodyFatSampleImport? in
                    guard let quantity = sample as? HKQuantitySample else { return nil }
                    let raw = quantity.quantity.doubleValue(for: .percent())
                    guard let percent = BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: raw)
                    else { return nil }
                    let source = quantity.sourceRevision.source
                    return BodyFatSampleImport(
                        sampleUUID: quantity.uuid,
                        date: quantity.startDate,
                        bodyFatPercent: percent,
                        sourceName: source.name,
                        sourceBundleIdentifier: source.bundleIdentifier
                    )
                }
                let deletedIDs = (deleted ?? []).map(\.uuid)
                continuation.resume(
                    returning: BodyFatSyncDelta(
                        upserts: upserts,
                        deletedSampleUUIDs: deletedIDs,
                        newAnchorData: Self.encodeAnchor(newAnchor)
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    func startObserving(onChange: @escaping @Sendable () -> Void) async {
        guard isAvailable else { return }
        let healthStore = healthStore()
        if bodyMassObserver == nil {
            let query = HKObserverQuery(sampleType: Self.bodyMassType, predicate: nil) { _, completion, error in
                defer { completion() }
                guard error == nil else { return }
                onChange()
            }
            bodyMassObserver = query
            healthStore.execute(query)
        }
        if bodyFatObserver == nil {
            let query = HKObserverQuery(sampleType: Self.bodyFatType, predicate: nil) { _, completion, error in
                defer { completion() }
                guard error == nil else { return }
                onChange()
            }
            bodyFatObserver = query
            healthStore.execute(query)
        }
        for type in [Self.bodyMassType, Self.bodyFatType] where !backgroundEnabledTypes.contains(type) {
            do {
                try await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
                backgroundEnabledTypes.insert(type)
            } catch {
                // 尽力后台；失败不阻断前台追赶。
            }
        }
    }

    func stopObserving() async {
        let healthStore = healthStore()
        if let bodyMassObserver {
            healthStore.stop(bodyMassObserver)
            self.bodyMassObserver = nil
        }
        if let bodyFatObserver {
            healthStore.stop(bodyFatObserver)
            self.bodyFatObserver = nil
        }
        for type in backgroundEnabledTypes {
            do {
                try await healthStore.disableBackgroundDelivery(for: type)
            } catch {
                // 尽力清理；前台已停止观察。
            }
        }
        backgroundEnabledTypes.removeAll()
    }

    private func decodeAnchor(_ data: Data?) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func encodeAnchor(_ anchor: HKQueryAnchor?) -> Data? {
        guard let anchor else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }
}

enum BodyMassReadError: Error {
    case unavailable
}
