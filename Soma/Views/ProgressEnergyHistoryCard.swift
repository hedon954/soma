import Charts
import SwiftUI

struct ProgressEnergyHistoryCard: View {
    let snapshot: ProgressHistorySnapshot
    let showsSources: () -> Void
    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metricLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: showsSources) {
                HStack {
                    Image(systemName: "fork.knife").foregroundStyle(AppTheme.mealAccent)
                    Text("饮食与能量").font(.title3.weight(.semibold))
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
                    metric("已记录摄入", value: snapshot.window.period == .day ? snapshot.days.first?.intake.value : snapshot.averageIntake, estimated: false)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Divider().frame(height: 58)
                    }
                    metric("预估总消耗", value: snapshot.averageEstimate, estimated: true)
                }
                if snapshot.window.period != .day {
                    Text("摄入 \(snapshot.intakeDayCount) 天 · 估算 \(snapshot.estimateDayCount) 天")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    chart
                    legend
                    if let bucket = selectedBucket {
                        NavigationLink {
                            InsightsView(initialPeriod: snapshot.window.period == .year ? .month : .day, initialDate: bucket.start)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(bucket.start.formatted(snapshot.window.period == .year ? .dateTime.year().month() : .dateTime.month().day().weekday()))
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(snapshot.window.period == .year ? "查看该月" : "查看当天")
                                    Image(systemName: "chevron.right")
                                }
                                Text("摄入 \(energyText(bucket.intake, missing: "未记录")) · 消耗 \(energyText(bucket.estimate, missing: "待估算"))")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progress-selected-period")
                    }
                } else if let day = snapshot.days.first {
                    metricLayout {
                        Text("与预估的差值").foregroundStyle(.secondary)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer()
                        }
                        Text(balanceText(day))
                    }.font(.subheadline)
                    metricLayout {
                        nutrient("蛋白质", day.protein.value)
                        nutrient("碳水", day.carbs.value)
                        nutrient("脂肪", day.fat.value)
                    }
                }
            }
        }
        .onChange(of: snapshot.window) { selectedDate = nil }
    }

    private func metric(_ title: String, value: Double?, estimated: Bool) -> some View {
        VStack(spacing: 9) {
            Text((snapshot.window.period == .day ? "" : "日均") + title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { (estimated ? "约 " : "") + text($0) } ?? (estimated ? "待估算" : "未记录"))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.6)
                if value != nil {
                    Text("kcal").font(.caption).fixedSize()
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private func nutrient(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(text(value)) g").font(.subheadline.monospacedDigit())
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
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
            if let bucket = selectedBucket {
                RuleMark(x: .value("所选日期", center(bucket)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary)
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
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
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

    private var selectedBucket: ProgressEnergyChartBucket? {
        if let selectedDate {
            return snapshot.energyBuckets.first { selectedDate >= $0.start && selectedDate < $0.end && $0.start <= Date.now }
        }
        return snapshot.energyBuckets.last { $0.intake != nil || $0.estimate != nil }
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

    private func energyText(_ value: Double?, missing: String) -> String {
        value.map { text($0) + " kcal" } ?? missing
    }

    private func balanceText(_ day: ProgressDailyMetrics) -> String {
        guard let estimate = day.energy.estimate else { return "待估算" }
        let difference = day.intake.value - estimate.totalKilocalories
        return difference.formatted(.number.sign(strategy: .always()).precision(.fractionLength(0))) + " kcal"
    }
}
