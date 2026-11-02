import SwiftUI

struct DailyActivityRecordDetailView: View {
    let workout: WorkoutEntry

    var body: some View {
        Form {
            Section {
                LabeledContent("日期", value: workout.date.formatted(date: .abbreviated, time: .omitted))
                ForEach(DailyActivityMetricKind.allCases, id: \.self) { kind in
                    LabeledContent(kind.title, value: "\(kind.displayValue(workout.dailyActivity?[kind].value)) \(kind.unit)")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("daily-metric-\(kind.rawValue)")
                }
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .foregroundStyle(AppTheme.accent)
        .navigationTitle("日常活动")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .appPageBackground()
    }
}
