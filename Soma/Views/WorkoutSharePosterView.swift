import SwiftUI

/// Fixed-width local export. Distinct training runs expand vertically without clipping.
struct WorkoutSharePosterView: View {
    let model: WorkoutSharePosterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 24) {
                overview
                details
                footer
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(width: 390, alignment: .leading)
        .foregroundStyle(WorkoutSharePalette.ink)
        .background(WorkoutSharePalette.paper)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Soma")
                    .font(.system(size: 23, weight: .bold))
                Spacer(minLength: 8)
                Text(model.dateText)
                    .font(.system(size: 14))
            }
            .padding(.bottom, 6)
            Text(model.title)
                .font(.system(size: 43, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            if !model.focusMuscles.isEmpty {
                Text(model.focusMuscles.joined(separator: " · "))
                    .font(.system(size: 16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
    }

    private var overview: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                volume
                    .frame(width: 160, alignment: .leading)
                MuscleMapView(
                    intensities: model.intensities,
                    showsBothSides: true,
                    showsLabels: false,
                    height: 210,
                    presentation: .poster
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.top, 18)

            statistics
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
                .background(WorkoutSharePalette.paper, in: RoundedRectangle(cornerRadius: 12))
                .padding(4)
        }
        .background(WorkoutSharePalette.hero, in: RoundedRectangle(cornerRadius: 14))
    }

    private var volume: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.volumeValue)
                    .font(.custom("DINCondensed-Bold", size: 110))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                Text("kg")
                    .font(.custom("DINCondensed-Bold", size: 26))
                    .fixedSize()
            }
            Rectangle()
                .frame(height: 0.5)
            Text("有效容量")
                .font(.system(size: 16, weight: .medium))
        }
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                metric("\(model.completedSets)", unit: "组", label: "完成组数")
                    .frame(width: 76, alignment: .leading)
                statRule
                metric(model.estimatedCalories.map(String.init) ?? "—", unit: "kcal", label: "预计消耗")
                    .frame(width: 88, alignment: .leading)
                statRule
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.durationText)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("总耗时")
                        .font(.system(size: 13))
                        .foregroundStyle(WorkoutSharePalette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.partialSets > 0 || model.failedSets > 0 {
                Text("部分完成 \(model.partialSets) 组 · 未完成 \(model.failedSets) 组")
                    .font(.system(size: 12))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
            }
        }
    }

    private var statRule: some View {
        Rectangle()
            .fill(WorkoutSharePalette.rule)
            .frame(width: 0.5, height: 56)
    }

    private func metric(_ value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.system(size: 12))
                    .fixedSize()
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WorkoutSharePalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("训练明细")
                    .font(.system(size: 18, weight: .bold))
                    .fixedSize()
                Rectangle()
                    .fill(WorkoutSharePalette.hero)
                    .frame(height: 1)
            }
            .padding(.bottom, 4)
            if model.exercises.isEmpty {
                Text("暂无可分享的动作记录")
                    .font(.system(size: 14))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.exercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func exerciseRow(_ exercise: WorkoutSharePosterModel.ExerciseLine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(exercise.setCount)组")
                    .font(.system(size: 12))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(exercise.loadGroups.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(.system(size: 14).monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(WorkoutSharePalette.paper, in: RoundedRectangle(cornerRadius: 8))
                }
                if exercise.loadGroups.isEmpty {
                    Text("组次未记录")
                        .font(.system(size: 13))
                        .foregroundStyle(WorkoutSharePalette.secondaryInk)
                }
            }
            if exercise.partialSetCount > 0 {
                Text("含 \(exercise.partialSetCount) 组部分完成")
                    .font(.system(size: 12))
                    .foregroundStyle(WorkoutSharePalette.secondaryInk)
            }
        }
        .padding(12)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(WorkoutSharePalette.hero)
                .frame(width: 28, height: 3)
            Text("本地训练记录")
                .font(.system(size: 11))
                .foregroundStyle(WorkoutSharePalette.secondaryInk)
        }
        .padding(.horizontal, 10)
    }
}
