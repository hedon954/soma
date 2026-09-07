import Charts
import SwiftUI

struct ProgressEnergyHistoryCard: View {
    let snapshot: ProgressHistorySnapshot
    let showsSources: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metricLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: showsSources) {
                HStack {
                    Image(systemName: "fork.knife").foregroundStyle(AppTheme.mealAccent)
                    Text("饮食与能量").font(.title3.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("饮食与能量，查看估算依据")

            if snapshot.days.first?.isFuture == true {
                ContentUnavailableView("尚未发生", systemImage: "calendar")
            } else {
                metricLayout {
                    ProgressEnergyBreakdownDisclosure(snapshot: snapshot, kind: .intake) {
                        metric(
                            "已记录摄入",
                            value: snapshot.window.period == .day
                                ? snapshot.days.first?.intake.value
                                : snapshot.averageIntake,
                            estimated: false
                        )
                    }
                    ProgressEnergyBreakdownDisclosure(snapshot: snapshot, kind: .expenditure) {
                        metric("预估总消耗", value: snapshot.averageEstimate, estimated: true)
                    }
                }
                if snapshot.window.period != .day {
                    Text("摄入 \(snapshot.intakeDayCount) 天 · 估算 \(snapshot.estimateDayCount) 天")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    chart
                    legend
                }
                if snapshot.window.period == .day, let rings = snapshot.nutritionRings {
                    ProgressNutritionRingsView(rings: rings, snapshot: snapshot)
                        .accessibilityIdentifier("progress-nutrition-rings")
                } else if snapshot.window.period == .day, let day = snapshot.days.first {
                    metricLayout {
                        nutrient("蛋白质", day.protein.value)
                        nutrient("碳水", day.carbs.value)
                        nutrient("脂肪", day.fat.value)
                    }
                }
            }
        }
        .padding(18)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func metric(_ title: String, value: Double?, estimated: Bool) -> some View {
        let tint = estimated ? AppTheme.mealSoftTint : AppTheme.trainingSoftTint
        let accent = estimated ? AppTheme.mealAccent : AppTheme.trainingAccent
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: estimated ? "target" : "flame.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(AppTheme.insetBackground, in: Circle())
                .background {
                    Circle()
                        .fill(tint)
                        .padding(-4)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text((snapshot.window.period == .day ? "" : "日均") + title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value.map { (estimated ? "约 " : "") + text($0) } ?? (estimated ? "待估算" : "未记录"))
                        .font(.title3.weight(.medium).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if value != nil {
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func nutrient(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(text(value)) g").font(.subheadline.monospacedDigit())
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var chart: some View {
        Chart {
            ForEach(snapshot.energyBuckets) { bucket in
                if let intake = bucket.intake {
                    RectangleMark(
                        xStart: .value("开始", bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) * 0.2)),
                        xEnd: .value("结束", bucket.end.addingTimeInterval(-bucket.end.timeIntervalSince(bucket.start) * 0.2)),
                        yStart: .value("基线", 0), yEnd: .value("已记录摄入", intake)
                    )
                    .foregroundStyle(AppTheme.mealAccent)
                }
                if let estimate = bucket.estimate {
                    // Isolated missing days remain gaps, not interpolated facts.
                    LineMark(x: .value("日期", center(bucket)), y: .value("预估消耗", estimate), series: .value("连续区间", segment(bucket)))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(AppTheme.mealAccent)
                    PointMark(x: .value("日期", center(bucket)), y: .value("预估消耗", estimate))
                        .symbolSize(10).foregroundStyle(AppTheme.mealAccent)
                }
            }
        }
        .chartXScale(domain: snapshot.window.start ... snapshot.window.end)
        .chartYScale(domain: 0 ... max(1000, maximum * 1.12))
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(AppTheme.separator)
                AxisValueLabel()
            }
        }
        .frame(height: 225)
        .accessibilityLabel("摄入与预估总消耗，单位千卡")
        .accessibilityIdentifier("progress-energy-chart")
    }

    private var legend: some View {
        HStack(spacing: 24) {
            Label { Text("已记录摄入") } icon: { RoundedRectangle(cornerRadius: 2).fill(AppTheme.mealAccent).frame(width: 16, height: 8) }
            Label { Text("预估总消耗") } icon: { Text("┄").foregroundStyle(AppTheme.mealAccent) }
        }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }

    private var maximum: Double {
        snapshot.energyBuckets.flatMap { [$0.intake, $0.estimate].compactMap { $0 } }.max() ?? 0
    }

    private var axisDates: [Date] {
        snapshot.energyBuckets.enumerated().compactMap { index, bucket in
            snapshot.window.period == .month && index % 5 != 0 ? nil : center(bucket)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        switch snapshot.window.period {
        case .week: date.formatted(.dateTime.weekday(.narrow))
        case .year: String(Calendar.current.component(.month, from: date))
        case .day, .month: date.formatted(.dateTime.day())
        }
    }

    private func center(_ bucket: ProgressEnergyChartBucket) -> Date {
        bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2)
    }

    private func segment(_ bucket: ProgressEnergyChartBucket) -> Int {
        snapshot.energyBuckets.prefix { $0.start < bucket.start }.count { $0.estimate == nil }
    }

    private func text(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0))) ?? "未记录"
    }
}
