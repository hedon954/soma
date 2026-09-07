import SwiftUI

struct ProgressNutritionRingsView: View {
    let rings: ProgressNutritionRings
    let snapshot: ProgressHistorySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 18) {
            ring(RingLayout(
                title: nil,
                accessibilityTitle: "热量",
                progress: rings.calories,
                metricColor: AppTheme.mealAccent,
                glyph: nil,
                unit: "kcal",
                size: 156,
                glow: .primary,
                showsCalorieStatus: true,
                breakdownKind: .intake,
                accessibilityIdentifier: "progress-calories-ring-breakdown"
            ))
            let macros: AnyLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            macros {
                ring(RingLayout(
                    title: "蛋白质",
                    accessibilityTitle: "蛋白质",
                    progress: rings.protein,
                    metricColor: AppTheme.vitalAccent,
                    glyph: .protein,
                    unit: "g",
                    size: 100,
                    glow: .secondary,
                    showsCalorieStatus: false,
                    breakdownKind: .protein,
                    accessibilityIdentifier: "progress-protein-ring-breakdown"
                ))
                ring(RingLayout(
                    title: "碳水",
                    accessibilityTitle: "碳水",
                    progress: rings.carbs,
                    metricColor: AppTheme.trainingAccent,
                    glyph: .carbs,
                    unit: "g",
                    size: 100,
                    glow: .secondary,
                    showsCalorieStatus: false,
                    breakdownKind: .carbs,
                    accessibilityIdentifier: "progress-carbs-ring-breakdown"
                ))
                ring(RingLayout(
                    title: "脂肪",
                    accessibilityTitle: "脂肪",
                    progress: rings.fat,
                    metricColor: AppTheme.trendAccent,
                    glyph: .fat,
                    unit: "g",
                    size: 100,
                    glow: .secondary,
                    showsCalorieStatus: false,
                    breakdownKind: .fat,
                    accessibilityIdentifier: "progress-fat-ring-breakdown"
                ))
            }
            if let remaining = remainingCalories {
                remainingCaption(remaining)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress-nutrition-rings")
    }

    private func ring(_ layout: RingLayout) -> some View {
        ProgressEnergyBreakdownDisclosure(
            snapshot: snapshot,
            kind: layout.breakdownKind,
            disclosureIdentifier: layout.accessibilityIdentifier
        ) {
            VStack(spacing: 8) {
                ZStack {
                    ProgressMetricRingShape(
                        progress: layout.progress,
                        metricColor: layout.metricColor,
                        lineWidth: layout.lineWidth,
                        glow: layout.glow
                    )
                    if layout.showsCalorieStatus {
                        calorieCenter(layout.progress)
                    } else {
                        macroCenter(layout)
                    }
                }
                .frame(width: layout.canvas, height: layout.canvas)
                if let title = layout.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                ringAccessibilityLabel(
                    layout.accessibilityTitle,
                    layout.progress,
                    layout.unit,
                    showsCalorieStatus: layout.showsCalorieStatus
                )
            )
            .accessibilityHint("查看组成明细")
        }
    }

    private func calorieCenter(_ progress: NutritionRingProgress) -> some View {
        VStack(spacing: 2) {
            Text("\(text(progress.intake)) / \(progress.target.map(text) ?? "—")")
                .font(.title2.weight(.medium).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("kcal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }

    private func macroCenter(_ layout: RingLayout) -> some View {
        VStack(spacing: 3) {
            if let glyph = layout.glyph {
                NutritionMacroIcon(glyph: glyph)
                    .foregroundStyle(layout.metricColor)
            }
            Text("\(text(layout.progress.intake)) / \(layout.progress.target.map(text) ?? "—") \(layout.unit)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
        }
        .padding(18)
    }

    private func remainingCaption(_ remaining: RemainingCaloriesCaption) -> some View {
        HStack(spacing: 8) {
            remainingIcon
            (
                Text(remaining.prefix)
                    + Text(remaining.value).foregroundStyle(AppTheme.mealAccent)
                    + Text(remaining.suffix)
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.accent)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background {
            Capsule(style: .continuous)
                .fill(AppTheme.mealSoftTint)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(AppTheme.mealAccent.opacity(0.28), lineWidth: 0.6)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.accessibilityLabel)
        .accessibilityIdentifier("progress-calorie-remaining")
    }

    private var remainingIcon: some View {
        Image(systemName: "lightbulb.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.mealAccent)
            .frame(width: 22, height: 22)
            .background(AppTheme.insetBackground, in: Circle())
            .accessibilityHidden(true)
    }

    private var remainingCalories: RemainingCaloriesCaption? {
        guard snapshot.window.period == .day,
              let remaining = CalorieRingStatusCopy(progress: rings.calories).remainingKilocalories
        else {
            return nil
        }
        let value = text(remaining)
        let isToday = snapshot.days.first.map { Calendar.current.isDateInToday($0.date) } ?? false
        return RemainingCaloriesCaption(
            prefix: isToday ? "今日热量仍可摄入约 " : "热量仍可摄入约 ",
            value: value,
            suffix: " kcal"
        )
    }

    private func ringAccessibilityLabel(
        _ title: String,
        _ progress: NutritionRingProgress,
        _ unit: String,
        showsCalorieStatus: Bool
    ) -> String {
        let intake = "\(text(progress.intake)) \(unit)"
        if let target = progress.target {
            let prefix = showsCalorieStatus ? "\(title)已摄入 \(intake)，推荐摄入 \(text(target)) \(unit)" : "\(title) \(intake)，目标 \(text(target)) \(unit)"
            return "\(prefix)，\(progress.status.accessibilityLabel)"
        }
        return "\(title) \(intake)，没有推荐目标"
    }

    private func text(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct RingLayout {
    var title: String?
    var accessibilityTitle: String
    var progress: NutritionRingProgress
    var metricColor: Color
    var glyph: NutritionMacroGlyph?
    var unit: String
    var size: CGFloat
    var glow: ProgressMetricRingGlow
    var showsCalorieStatus: Bool
    var breakdownKind: ProgressEnergyBreakdown.Kind
    var accessibilityIdentifier: String

    var lineWidth: CGFloat {
        glow == .primary ? 12 : 7
    }

    var canvas: CGFloat {
        size + glow.outset * 2
    }
}

private struct RemainingCaloriesCaption {
    let prefix: String
    let value: String
    let suffix: String

    var accessibilityLabel: String {
        prefix + value + suffix
    }
}

private enum ProgressMetricRingGlow {
    case primary
    case secondary

    var outset: CGFloat {
        switch self {
        case .primary: 10
        case .secondary: 4
        }
    }
}

private struct ProgressMetricRingShape: View {
    let progress: NutritionRingProgress
    let metricColor: Color
    let lineWidth: CGFloat
    let glow: ProgressMetricRingGlow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let canvas = min(geometry.size.width, geometry.size.height)
            let inset = glow.outset
            let isDark = colorScheme == .dark
            ZStack {
                Circle()
                    .stroke(AppTheme.insetBackground, lineWidth: lineWidth)
                    .padding(inset)
                if fill > 0 {
                    if glow == .primary {
                        arc(width: lineWidth + 2, color: progressColor.opacity(isDark ? 0.28 : 0.14))
                            .padding(inset)
                            .blur(radius: 1)
                    } else {
                        arc(width: lineWidth + 1.5, color: progressColor.opacity(isDark ? 0.16 : 0.1))
                            .padding(inset)
                            .blur(radius: 0.8)
                    }
                    Circle()
                        .trim(from: 0, to: fill)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                }
            }
            .frame(width: canvas, height: canvas)
        }
    }

    private var fill: CGFloat {
        guard let target = progress.target, target > 0 else {
            return 0
        }
        return CGFloat(min(max(progress.intake / target, 0), 1))
    }

    private var progressColor: Color {
        switch progress.status {
        case .over:
            AppTheme.vitalAccent
        case .under, .onTarget, .noTarget:
            metricColor
        }
    }

    private func arc(width: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: fill)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}
