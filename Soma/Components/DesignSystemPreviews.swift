#if DEBUG
    import SwiftUI

    private struct SomaDesignSystemPreviewGallery: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeading(title: "最近活动与训练建议")

                    AppCard {
                        VStack(alignment: .leading, spacing: AppTheme.groupSpacing) {
                            Label("训练节奏稳定", systemImage: "waveform.path.ecg")
                                .font(.headline)
                                .foregroundStyle(AppTheme.trainingAccent)
                            Text("这是一段用于检查长中文、自动换行与卡片内边距的说明文字。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: AppTheme.groupSpacing) {
                        MetricTile(
                            icon: "dumbbell.fill",
                            value: "3",
                            label: "次训练",
                            tint: AppTheme.trainingAccent
                        )
                        MetricTile(
                            icon: "scalemass.fill",
                            value: "—",
                            label: "未记录",
                            tint: AppTheme.bodyAccent
                        )
                    }

                    EmptyStateCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "还没有可靠趋势",
                        message: "继续记录即可；Soma 不会用默认值补齐缺失事实。"
                    )
                }
                .padding(AppTheme.pagePadding)
                .frame(maxWidth: AppTheme.readableContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .appPageBackground()
        }
    }

    private struct SomaComponentStatePreviewGallery: View {
        @State private var editableDraft = WorkoutRecordDraft(evidence: [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: WorkoutEffortSide.none,
                targetKind: .duration,
                durationSeconds: 60,
                externalWeightKG: 0,
                restSeconds: 60
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                side: .left,
                targetKind: .repetitions,
                reps: 10,
                externalWeightKG: 16,
                restSeconds: 15
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                side: .right,
                targetKind: .repetitions,
                reps: 10,
                externalWeightKG: 16,
                restSeconds: 75
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 3,
                side: .left,
                targetKind: .repetitions,
                reps: nil,
                externalWeightKG: nil,
                restSeconds: nil
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 4,
                side: .right,
                targetKind: .duration,
                durationSeconds: 45,
                externalWeightKG: nil,
                restSeconds: 45
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 5,
                side: WorkoutEffortSide.none,
                targetKind: .repetitions,
                reps: 0,
                externalWeightKG: 1001,
                restSeconds: 4000
            )
        ])

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    ProgressWeekSummaryCard(
                        trainingCount: 3,
                        volume: nil,
                        weightChange: nil,
                        trainingDays: [
                            Calendar.current.startOfDay(for: .now),
                            Calendar.current.startOfDay(
                                for: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
                            )
                        ]
                    )

                    ProgressConclusionCard(
                        title: "训练节奏正在形成",
                        detail: "这是一段用于检查较长中文结论在大字号、窄屏和浅深主题下能否自然换行的依据说明。",
                        status: .attention
                    )

                    AppCard {
                        ProgressRecentActivityRow(activity: ProgressRecentActivity(
                            id: UUID(),
                            kind: .workout,
                            date: .now,
                            title: "保加利亚分腿蹲（左侧稳定控制）",
                            detail: "缺少可靠训练容量，不补默认值",
                            metric: nil
                        ))
                    }

                    SectionHeading(title: "可编辑训练记录")
                    WorkoutLogicalGroupsEditor(
                        draft: $editableDraft,
                        isEditable: true
                    )

                    SectionHeading(title: "旧消息锁定")
                    WorkoutLogicalGroupsEditor(
                        draft: .constant(editableDraft),
                        isEditable: false
                    )
                }
                .padding(AppTheme.pagePadding)
                .frame(maxWidth: AppTheme.readableContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .appPageBackground()
        }
    }

    #Preview("Soma 设计系统 · 浅色") {
        SomaDesignSystemPreviewGallery()
            .preferredColorScheme(.light)
    }

    #Preview("Soma 设计系统 · 深色") {
        SomaDesignSystemPreviewGallery()
            .preferredColorScheme(.dark)
    }

    #Preview("Soma 设计系统 · 辅助字号") {
        SomaDesignSystemPreviewGallery()
            .preferredColorScheme(.light)
            .dynamicTypeSize(.accessibility3)
    }

    #Preview("Soma 组件状态 · 浅色") {
        SomaComponentStatePreviewGallery()
            .preferredColorScheme(.light)
    }

    #Preview("Soma 组件状态 · 深色") {
        SomaComponentStatePreviewGallery()
            .preferredColorScheme(.dark)
    }

    #Preview("Soma 组件状态 · 辅助字号") {
        SomaComponentStatePreviewGallery()
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.accessibility3)
    }
#endif
