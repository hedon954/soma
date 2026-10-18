import SwiftData
import SwiftUI

struct CoachScheduleDraftCard: View {
    let payload: TrainingScheduleDraftPayload
    @Query private var schedules: [TrainingSchedule]
    @State private var editorDraft: TrainingScheduleEditorDraft?
    @State private var showsEditor = false

    init(payload: TrainingScheduleDraftPayload) {
        self.payload = payload
        let activeSchedule = TrainingScheduleStatus.active.rawValue
        var scheduleDescriptor = FetchDescriptor<TrainingSchedule>(
            predicate: #Predicate { $0.statusRaw == activeSchedule }
        )
        scheduleDescriptor.fetchLimit = 1
        _schedules = Query(scheduleDescriptor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accent)
            Text("开始日 \(TrainingScheduleDraftDates.label(payload.anchorDate))")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
            ForEach(Array(payload.dayTitles.enumerated()), id: \.offset) { index, title in
                Text("第 \(index + 1) 天 · \(title)")
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(AppTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if schedules.first != nil {
                Text("保存会把现在进行中的计划归档。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
            Button("查看并修改") {
                editorDraft = payload.editorDraft()
                showsEditor = true
            }
            .appPrimaryButtonStyle()
            .accessibilityHint("打开训练计划编辑器，保存后才会写入")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showsEditor) {
            NavigationStack {
                TrainingScheduleEditorView(schedule: nil, draft: editorDraft)
            }
        }
    }
}
