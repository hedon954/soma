import Charts
import SwiftUI

struct ProgressMuscleWorkloadView: View {
    let rows: [ProgressMuscleWorkload]

    var body: some View {
        Chart(rows) { row in
            BarMark(x: .value("工作组", row.primarySets), y: .value("肌群", row.name))
                .foregroundStyle(by: .value("角色", "主要"))
            BarMark(x: .value("工作组", row.secondarySets), y: .value("肌群", row.name))
                .foregroundStyle(by: .value("角色", "辅助"))
        }
        .chartForegroundStyleScale(["主要": AppTheme.trainingAccent, "辅助": AppTheme.trainingAccent.opacity(0.45)])
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: CGFloat(rows.count) * 32 + 50)
        .accessibilityLabel("肌群工作组，区分主要和辅助")
    }
}
