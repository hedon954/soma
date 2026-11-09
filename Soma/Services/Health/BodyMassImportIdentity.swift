import Foundation

enum BodyMassImportIdentity {
    static let externalSource = "appleHealth"
    static let cursorSource = "appleHealth"
    static let bodyMassStream = "bodyMass"
    static let bodyFatStream = "bodyFat"

    /// 兼容旧调用：默认体重游标流。
    static let cursorStream = bodyMassStream

    static let bodyMassExternalIDPrefix = "bodyMass:"
    static let bodyFatExternalIDPrefix = "bodyFat:"

    static func externalID(sampleUUID: UUID) -> String {
        bodyMassExternalID(sampleUUID: sampleUUID)
    }

    static func bodyMassExternalID(sampleUUID: UUID) -> String {
        bodyMassExternalIDPrefix + sampleUUID.uuidString
    }

    static func bodyFatExternalID(sampleUUID: UUID) -> String {
        bodyFatExternalIDPrefix + sampleUUID.uuidString
    }

    static func sampleUUID(externalID: String) -> UUID? {
        if externalID.hasPrefix(bodyMassExternalIDPrefix) {
            return UUID(uuidString: String(externalID.dropFirst(bodyMassExternalIDPrefix.count)))
        }
        if externalID.hasPrefix(bodyFatExternalIDPrefix) {
            return UUID(uuidString: String(externalID.dropFirst(bodyFatExternalIDPrefix.count)))
        }
        return nil
    }
}

/// HealthKit `.percent()`：1.0 = 100%。转换为 BodyEntry 使用的百分点（0…100）。
enum BodyFatPercentageConversion {
    static func percentPoints(fromHealthKitPercentUnit raw: Double) -> Double? {
        guard raw.isFinite, raw > 0 else { return nil }
        let points: Double
        if raw <= 1 {
            points = raw * 100
        } else if raw <= 100 {
            // 少数来源可能已按百分点写入；避免再乘 100。
            points = raw
        } else {
            return nil
        }
        guard points > 0, points <= 100 else { return nil }
        return points
    }
}

enum BodyMassKnownSource: Equatable, Sendable {
    case keep
    case appleHealth
    case unknown(displayName: String)

    var accessibilityLabel: String {
        switch self {
        case .keep: "Keep 来源"
        case .appleHealth: "Apple 健康"
        case let .unknown(name): name.isEmpty ? "未知来源" : name
        }
    }

    /// 列表次要文案：简洁来源名；诚实说明见 `accessibilityLabel` 与品牌文档。
    var listCaption: String {
        switch self {
        case .keep: "Keep"
        case .appleHealth: "Apple 健康"
        case let .unknown(name): name.isEmpty ? "未知来源" : name
        }
    }

    var accessibilityIdentifierSuffix: String {
        switch self {
        case .keep: "keep"
        case .appleHealth: "apple"
        case .unknown: "unknown"
        }
    }

    static func resolve(name: String?, bundleIdentifier: String?) -> BodyMassKnownSource {
        let combined = [name, bundleIdentifier]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let nameLower = name?.lowercased() ?? ""
        let bundleLower = bundleIdentifier?.lowercased() ?? ""
        if bundleLower.contains("gotokeep")
            || nameLower == "keep"
            || nameLower.hasPrefix("keep ")
            || nameLower.contains(" keep")
        {
            return .keep
        }
        if combined.contains("com.apple.health")
            || combined.contains("apple health")
            || combined.contains("health") && (bundleIdentifier?.contains("com.apple") == true)
            || name == "Health"
            || name == "健康"
        {
            return .appleHealth
        }
        let display = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .unknown(displayName: display.isEmpty ? (bundleIdentifier ?? "") : display)
    }
}

struct BodyMassSampleImport: Equatable, Sendable {
    var sampleUUID: UUID
    var date: Date
    var weightKilograms: Double
    var sourceName: String
    var sourceBundleIdentifier: String
}

struct BodyFatSampleImport: Equatable, Sendable {
    var sampleUUID: UUID
    var date: Date
    /// 百分点 0…100（非 HealthKit 0…1 分数）。
    var bodyFatPercent: Double
    var sourceName: String
    var sourceBundleIdentifier: String
}

struct BodyMassSyncDelta: Equatable, Sendable {
    var upserts: [BodyMassSampleImport]
    var deletedSampleUUIDs: [UUID]
    var newAnchorData: Data?
}

struct BodyFatSyncDelta: Equatable, Sendable {
    var upserts: [BodyFatSampleImport]
    var deletedSampleUUIDs: [UUID]
    var newAnchorData: Data?
}
