import Foundation
import HealthKit

protocol BodyMassReading: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func pull(anchorData: Data?) async throws -> BodyMassSyncDelta
    func startObserving(onChange: @escaping @Sendable () -> Void) async
    func stopObserving() async
}

actor HealthKitBodyMassReader: BodyMassReading {
    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var store: HKHealthStore?
    private var observerQuery: HKObserverQuery?
    private var backgroundEnabled = false

    static let bodyMassType = HKQuantityType(.bodyMass)

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
        try await healthStore().requestAuthorization(toShare: [], read: [Self.bodyMassType])
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

    func startObserving(onChange: @escaping @Sendable () -> Void) async {
        guard isAvailable else { return }
        let healthStore = healthStore()
        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: Self.bodyMassType, predicate: nil) { _, completion, _ in
                onChange()
                completion()
            }
            observerQuery = query
            healthStore.execute(query)
        }
        guard !backgroundEnabled else { return }
        do {
            try await healthStore.enableBackgroundDelivery(for: Self.bodyMassType, frequency: .immediate)
            backgroundEnabled = true
        } catch {
            // 尽力后台；失败不阻断前台追赶。
        }
    }

    func stopObserving() async {
        let healthStore = healthStore()
        if let observerQuery {
            healthStore.stop(observerQuery)
            self.observerQuery = nil
        }
        if backgroundEnabled {
            do {
                try await healthStore.disableBackgroundDelivery(for: Self.bodyMassType)
            } catch {
                // 尽力清理；前台已停止观察。
            }
            backgroundEnabled = false
        }
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
