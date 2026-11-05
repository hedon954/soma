import Foundation

/// 同一自然日、同一来源的三项候选整包（ADR 0146）。
struct DailyActivityCandidatePackage: Equatable, Sendable {
    var key: DailyActivityDayKey
    var winningSource: DailyActivityWinningSource
    var steps: Double?
    var walkingRunningDistance: Double?
    var activeEnergy: Double?
    var readAt: Date
    /// 各指标用来源归因（图标 / 审查）；缺项保持 nil，不向其他来源借数。
    var sourceByMetric: [DailyActivityMetricKind: ActivitySourceAttribution] = [:]

    /// 至少含可用步数才算可用整包候选。
    var isUsable: Bool {
        guard let steps, steps.isFinite, steps >= 0 else { return false }
        return true
    }

    func asSummary() -> DailyActivitySummary {
        var summary = DailyActivitySummary(key: key, winningSource: winningSource)
        apply(.steps, steps, to: &summary)
        apply(.walkingRunningDistance, walkingRunningDistance, to: &summary)
        apply(.activeEnergy, activeEnergy, to: &summary)
        return summary
    }

    private func apply(
        _ kind: DailyActivityMetricKind,
        _ value: Double?,
        to summary: inout DailyActivitySummary
    ) {
        summary[kind].replace(value: value, readAt: readAt)
        if let attribution = sourceByMetric[kind] {
            summary[kind].source = attribution
        }
    }
}

enum DailyActivityPackageSelector {
    /// 按策略在可用整包间择优；落选包任何指标不得补进获胜包。
    static func select(
        preference: DailyActivitySourcePreference,
        apple: DailyActivityCandidatePackage?,
        coros: DailyActivityCandidatePackage?
    ) -> DailyActivityCandidatePackage? {
        let appleOK = apple.flatMap { $0.isUsable ? $0 : nil }
        let corosOK = coros.flatMap { $0.isUsable ? $0 : nil }
        switch preference {
        case .apple:
            return appleOK ?? apple
        case .coros:
            return corosOK ?? appleOK ?? apple
        case .maxSteps:
            switch (corosOK, appleOK) {
            case let (c?, a?):
                if c.steps! > a.steps! { return c }
                if a.steps! > c.steps! { return a }
                // 平手：稳定次序 coros > apple
                return c
            case let (c?, nil):
                return c
            case let (nil, a?):
                return a
            case (nil, nil):
                return apple ?? coros
            }
        }
    }

    static func applePackage(
        from summary: DailyActivitySummary,
        readAt: Date = .now
    ) -> DailyActivityCandidatePackage {
        DailyActivityCandidatePackage(
            key: summary.key,
            winningSource: .appleHealth,
            steps: summary[.steps].value,
            walkingRunningDistance: summary[.walkingRunningDistance].value,
            activeEnergy: summary[.activeEnergy].value,
            readAt: readAt,
            sourceByMetric: Dictionary(uniqueKeysWithValues: DailyActivityMetricKind.allCases.compactMap { kind in
                summary[kind].source.map { (kind, $0) }
            })
        )
    }

    static func corosPackage(
        key: DailyActivityDayKey,
        contributions: [DailyActivityMetricKind: [DailyActivitySourceContribution]],
        readAt: Date
    ) -> DailyActivityCandidatePackage? {
        func corosValue(_ kind: DailyActivityMetricKind) -> (Double?, ActivitySourceAttribution?) {
            let matches = (contributions[kind] ?? []).filter { DailyActivitySourceMatcher.isCOROS($0.source) }
            guard !matches.isEmpty else { return (nil, nil) }
            let sum = matches.compactMap(\.value).filter { $0.isFinite && $0 >= 0 }.reduce(0, +)
            let hasAny = matches.contains { $0.value != nil }
            let attribution = ActivitySourceAttribution(
                sources: matches.map(\.source),
                readAt: readAt
            )
            return (hasAny ? sum : nil, attribution)
        }
        let (steps, stepsSource) = corosValue(.steps)
        let (distance, distanceSource) = corosValue(.walkingRunningDistance)
        let (energy, energySource) = corosValue(.activeEnergy)
        guard steps != nil else { return nil }
        var sourceByMetric: [DailyActivityMetricKind: ActivitySourceAttribution] = [:]
        if let stepsSource { sourceByMetric[.steps] = stepsSource }
        if let distanceSource { sourceByMetric[.walkingRunningDistance] = distanceSource }
        if let energySource { sourceByMetric[.activeEnergy] = energySource }
        return DailyActivityCandidatePackage(
            key: key,
            winningSource: .coros,
            steps: steps,
            walkingRunningDistance: distance,
            activeEnergy: energy,
            readAt: readAt,
            sourceByMetric: sourceByMetric
        )
    }

    /// 回看窗口内是否存在 COROS 日活动来源（至少步数相关贡献）。
    static func hasCOROSSamples(
        contributions: [DailyActivityDayKey: [DailyActivityMetricKind: [DailyActivitySourceContribution]]]
    ) -> Bool {
        for day in contributions.values {
            for kind in DailyActivityMetricKind.allCases {
                if (day[kind] ?? []).contains(where: { DailyActivitySourceMatcher.isCOROS($0.source) }) {
                    return true
                }
            }
        }
        return false
    }
}
