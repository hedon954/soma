import Foundation

enum BodyMassImportIdentity {
    static let externalSource = "appleHealth"
    static let cursorSource = "appleHealth"
    static let cursorStream = "bodyMass"

    static func externalID(sampleUUID: UUID) -> String {
        "bodyMass:" + sampleUUID.uuidString
    }

    static func sampleUUID(externalID: String) -> UUID? {
        guard externalID.hasPrefix("bodyMass:") else { return nil }
        return UUID(uuidString: String(externalID.dropFirst("bodyMass:".count)))
    }
}

enum BodyMassKnownSource: Equatable, Sendable {
    case keep
    case appleHealth
    case unknown(displayName: String)

    var accessibilityLabel: String {
        switch self {
        case .keep: "Keep 来源（自备识别标，非官方图标）"
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

struct BodyMassSyncDelta: Equatable, Sendable {
    var upserts: [BodyMassSampleImport]
    var deletedSampleUUIDs: [UUID]
    var newAnchorData: Data?
}
