import SwiftUI

enum WorkoutShareCanvas {
    /// iPhone 17 Pro Max logical canvas (1320 × 2868 px @3x).
    static let width: CGFloat = 440
    static let height: CGFloat = 956
}

/// Fixed Pro Max paper. Long sessions compress into the same canvas instead of growing taller.
struct WorkoutSharePosterView: View {
    let model: WorkoutSharePosterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 12) {
                overview
                details
                Spacer(minLength: 0)
                footer
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: WorkoutShareCanvas.width, height: WorkoutShareCanvas.height, alignment: .topLeading)
        .foregroundStyle(WorkoutSharePalette.ink)
        .background(WorkoutSharePalette.paper)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Soma")
                    .font(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                Text(model.dateText)
                    .font(.system(size: 13))
            }
            Text(model.title)
                .font(.system(size: 28, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if !model.focusMuscles.isEmpty {
                Text(model.focusMuscles.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 6)
    }

    private var overview: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                volume
                    .frame(width: 168, alignment: .leading)
                MuscleMapView(
                    intensities: model.intensities,
                    showsBothSides: true,
                    showsLabels: false,
                    height: 132,
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

    private var volume: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.volumeValue)
                    .font(.custom("DINCondensed-Bold", size: 72))
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

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.exercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func exerciseRow(_ exercise: WorkoutSharePosterModel.ExerciseLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                if exercise.loadGroups.isEmpty {
                    Text("组次未记录")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkoutSharePalette.secondaryInk)
                } else {
                    Text(exercise.loadGroups.joined(separator: " · "))
                        .font(.system(size: 12).monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
                if exercise.partialSetCount > 0 {
                    Text("含 \(exercise.partialSetCount) 组部分完成")
                        .font(.system(size: 11))
                        .foregroundStyle(WorkoutSharePalette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(exercise.setCount)组")
                .font(.system(size: 11))
                .foregroundStyle(WorkoutSharePalette.secondaryInk)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 10))
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
