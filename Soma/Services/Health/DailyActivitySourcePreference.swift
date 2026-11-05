import Foundation

/// 设置「日活动数据源」持久化枚举（ADR 0146 / PRD 077）。
enum DailyActivitySourcePreference: String, CaseIterable, Identifiable, Sendable {
    case apple
    case coros
    case maxSteps

    static let defaultsKey = "health.dailyActivitySource"
    static let `default` = Self.apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple"
        case .coros: "COROS"
        case .maxSteps: "步数更大"
        }
    }

    /// 非品牌 SF Symbol；Apple / COROS 在 UI 用专用图标视图。
    var systemImage: String {
        switch self {
        case .apple: "heart.fill"
        case .coros: "watch.and.phone"
        case .maxSteps: "arrow.up.circle"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        guard let raw = defaults.string(forKey: defaultsKey),
              let value = Self(rawValue: raw)
        else { return .default }
        return value
    }

    static func set(_ preference: Self, in defaults: UserDefaults = .standard) {
        defaults.set(preference.rawValue, forKey: defaultsKey)
    }

    /// 若持久化为 `coros` 但当前无 COROS 样本，按 `apple` 行为，并纠正持久化。
    /// COROS 样本再次出现时不自动切回。
    @discardableResult
    static func resolveEffective(
        stored preference: Self,
        corosAvailable: Bool,
        defaults: UserDefaults = .standard
    ) -> Self {
        if preference == .coros, !corosAvailable {
            set(.apple, in: defaults)
            return .apple
        }
        return preference
    }

    /// 设置页可见选项：Apple / 步数更大始终；COROS 仅有样本时。
    static func visibleOptions(corosAvailable: Bool) -> [Self] {
        corosAvailable ? [.apple, .coros, .maxSteps] : [.apple, .maxSteps]
    }
}

/// 落盘与列表图标使用的获胜来源稳定标识。
enum DailyActivityWinningSource: String, Codable, Sendable, Equatable {
    case appleHealth
    case coros

    var preference: DailyActivitySourcePreference {
        switch self {
        case .appleHealth: .apple
        case .coros: .coros
        }
    }

    var title: String {
        preference.title
    }

    var externalSource: String { rawValue }
}

enum DailyActivitySourceMatcher {
    /// bundle / 名称匹配规则：与整包识别、COROS 选项可见性共用。
    static func isCOROS(_ source: HealthDataSource) -> Bool {
        let bundle = source.bundleIdentifier.lowercased()
        if bundle.contains("coros") { return true }
        let name = source.name.lowercased()
        return name.contains("coros") || source.name.contains("高驰")
    }

    static func isCOROS(name: String, bundleIdentifier: String) -> Bool {
        isCOROS(HealthDataSource(name: name, bundleIdentifier: bundleIdentifier))
    }
}
