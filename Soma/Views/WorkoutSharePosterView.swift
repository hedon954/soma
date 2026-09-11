import SwiftUI

struct WorkoutSharePosterView: View {
    let model: WorkoutSharePosterModel

    private var metrics: WorkoutSharePosterLayout.Metrics {
        WorkoutSharePosterLayout.metrics(exerciseCount: model.exercises.count)
    }

    var body: some View {
        WorkoutSharePosterPageLayout(spacing: metrics.sectionSpacing, minHeight: metrics.minBodyHeight) {
            header(metrics)
                .sharePosterSlot(.header)
            overview(metrics)
                .sharePosterSlot(.overview)
            details(metrics)
                .sharePosterSlot(.details)
            footer
                .sharePosterSlot(.footer)
        }
        .padding(.horizontal, WorkoutShareCanvas.horizontalPadding)
        .padding(.top, metrics.outerTop)
        .padding(.bottom, metrics.outerBottom)
        .frame(width: WorkoutShareCanvas.width, alignment: .topLeading)
        .foregroundStyle(WorkoutSharePalette.ink)
        .background(WorkoutSharePalette.paper)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private func header(_ metrics: WorkoutSharePosterLayout.Metrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Soma")
                    .font(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                Text(model.dateText)
                    .font(.system(size: 13))
            }
            Text(model.title)
                .font(.system(size: metrics.titleSize, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            if !model.focusMuscles.isEmpty {
                Text(model.focusMuscles.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
    }

    private func overview(_ metrics: WorkoutSharePosterLayout.Metrics) -> some View {
        VStack(spacing: metrics.overviewSpacing) {
            HStack(alignment: .center, spacing: 8) {
                volume(metrics)
                    .frame(width: 168, alignment: .leading)
                MuscleMapView(
                    intensities: model.intensities,
                    showsBothSides: true,
                    showsLabels: false,
                    height: metrics.muscleMapHeight,
                    presentation: .poster
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            statistics
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(WorkoutSharePalette.paper, in: RoundedRectangle(cornerRadius: 12))
                .padding(4)
        }
        .background(WorkoutSharePalette.hero, in: RoundedRectangle(cornerRadius: 14))
    }

    private func volume(_ metrics: WorkoutSharePosterLayout.Metrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.volumeValue)
                    .font(.custom("DINCondensed-Bold", size: metrics.volumeSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                Text("kg")
                    .font(.custom("DINCondensed-Bold", size: 20))
                    .fixedSize()
            }
            Rectangle()
                .frame(height: 0.5)
            Text("有效容量")
                .font(.system(size: 14, weight: .medium))
        }
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                metric("\(model.completedSets)", unit: "组", label: "完成组数")
                    .frame(width: 76, alignment: .leading)
                statRule
                metric(model.estimatedCalories.map(String.init) ?? "—", unit: "kcal", label: "预计消耗")
                    .frame(width: 88, alignment: .leading)
                statRule
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.durationText)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("总耗时")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkoutSharePalette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.partialSets > 0 || model.failedSets > 0 {
                Text("部分完成 \(model.partialSets) 组 · 未完成 \(model.failedSets) 组")
                    .font(.system(size: 11))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
            }
        }
    }

    private var statRule: some View {
        Rectangle()
            .fill(WorkoutSharePalette.rule)
            .frame(width: 0.5, height: 44)
    }

    private func metric(_ value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.system(size: 11))
                    .fixedSize()
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(WorkoutSharePalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ metrics: WorkoutSharePosterLayout.Metrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.detailSpacing) {
            HStack(spacing: 12) {
                Text("训练明细")
                    .font(.system(size: 16, weight: .bold))
                    .fixedSize()
                Rectangle()
                    .fill(WorkoutSharePalette.hero)
                    .frame(height: 1)
            }
            if model.exercises.isEmpty {
                Text("暂无可分享的动作记录")
                    .font(.system(size: 13))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(model.exercises) { exercise in
                        exerciseRow(exercise, metrics: metrics)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 6)
    }

    private func exerciseRow(
        _ exercise: WorkoutSharePosterModel.ExerciseLine,
        metrics: WorkoutSharePosterLayout.Metrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(exercise.name)
                    .font(.system(size: metrics.rowNameSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(exercise.setCount) 组")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
                    .fixedSize()
            }
            if exercise.loadGroups.isEmpty {
                Text("组次未记录")
                    .font(.system(size: metrics.rowMetaSize))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
            } else {
                WorkoutShareGroupLayout(spacing: 5) {
                    ForEach(Array(exercise.loadGroups.enumerated()), id: \.offset) { _, group in
                        Text(group)
                            .font(.system(size: metrics.rowMetaSize).monospacedDigit())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(WorkoutSharePalette.groupSurface, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            if exercise.partialSetCount > 0 {
                Text("含 \(exercise.partialSetCount) 组部分完成")
                    .font(.system(size: 11))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, metrics.rowVerticalPadding)
        .frame(maxHeight: .infinity, alignment: .center)
        .overlay {
            RoundedRectangle(cornerRadius: metrics.rowCornerRadius)
                .strokeBorder(WorkoutSharePalette.cardRule, lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(WorkoutSharePalette.hero)
                .frame(width: 28, height: 3)
            Text("本地训练记录")
                .font(.system(size: 11))
                .foregroundStyle(WorkoutSharePalette.secondaryInk)
        }
        .padding(.horizontal, 6)
    }
}
