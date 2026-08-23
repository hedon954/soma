import SwiftUI

struct WorkoutLogicalGroupsEditor: View {
    @Binding var draft: WorkoutRecordDraft
    let isEditable: Bool
    var fallbackRestSeconds: Int?

    private var runs: [WorkoutLogicalGroupRun] {
        draft.displayRuns
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.groupSpacing) {
            if runs.isEmpty {
                Text("尚未填写训练组")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(runs.enumerated()), id: \.element.id) { position, run in
                    logicalGroupCard(run, position: position)
                }
            }

            if isEditable {
                Button {
                    draft.appendGroup()
                } label: {
                    Label("添加一组", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: AppTheme.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.tint)
                .accessibilityHint("在末尾添加一个新的逻辑组")
            }
        }
    }

    private func logicalGroupCard(
        _ run: WorkoutLogicalGroupRun,
        position: Int
    ) -> some View {
        let group = run.representative
        let groupIDs = Set(run.groups.map(\.id))
        let effortCount = group.efforts.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                workoutChip(group.targetKindLabel)
                workoutChip(group.sideMode.displayName)
                Spacer(minLength: 6)
                if run.count > 1 {
                    Text("× \(run.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if isEditable {
                    Menu {
                        Button {
                            draft.appendGroup(copying: group.id)
                        } label: {
                            Label("复制这一组", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            for id in groupIDs {
                                draft.removeGroup(id: id)
                            }
                        } label: {
                            Label(
                                run.count > 1 ? "删除这批组" : "删除这一组",
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                    }
                    .accessibilityLabel("逻辑组操作")
                }
            }

            VStack(spacing: 0) {
                ForEach(group.efforts.indices, id: \.self) { effortIndex in
                    let restGroupIDs = run.restTargetGroupIDs(
                        effortIndex: effortIndex,
                        effortCount: effortCount,
                        finalGroupID: draft.finalGroupID
                    )
                    let evidenceRest = storedRest(
                        in: run,
                        groupIDs: restGroupIDs,
                        effortIndex: effortIndex
                    )
                    let displayRest = evidenceRest
                        ?? (effortIndex == effortCount - 1 ? fallbackRestSeconds : nil)
                    effortRow(
                        group.efforts[effortIndex],
                        groupIDs: groupIDs,
                        effortIndex: effortIndex,
                        sideMode: group.sideMode
                    )

                    let restLabel = restLabel(
                        at: effortIndex,
                        effortCount: effortCount,
                        sideMode: group.sideMode
                    )
                    if shouldShowRest(
                        evidenceRest,
                        effortIndex: effortIndex,
                        effortCount: effortCount,
                        hasTargets: !restGroupIDs.isEmpty
                    ) {
                        restRow(
                            restLabel,
                            groupIDs: restGroupIDs,
                            effortIndex: effortIndex,
                            value: displayRest,
                            fallbackValue: displayRest
                        )
                    } else if effortIndex < effortCount - 1 {
                        Divider()
                            .overlay(AppTheme.separator)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(
                    cornerRadius: AppTheme.controlRadius,
                    style: .continuous
                )
            )
        }
        .padding(14)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(
                cornerRadius: AppTheme.cardRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "第 \(position + 1) 个逻辑组，\(group.targetKindLabel)，\(group.sideMode.displayName)"
        )
    }

    private func effortRow(
        _ effort: WorkoutEffortDraft,
        groupIDs: Set<UUID>,
        effortIndex: Int,
        sideMode: WorkoutRecordSideMode
    ) -> some View {
        HStack(spacing: 10) {
            Text(sideLabel(effort.side, mode: sideMode))
                .font(.subheadline.weight(.medium))
                .frame(width: sideMode == .simultaneous ? 0 : 34, alignment: .leading)
                .opacity(sideMode == .simultaneous ? 0 : 1)
                .accessibilityHidden(sideMode == .simultaneous)

            if isEditable {
                WorkoutNumericField(
                    text: intBinding(
                        groupIDs: groupIDs,
                        effortIndex: effortIndex,
                        keyPath: effort.targetKind == .duration
                            ? \.durationSeconds
                            : \.reps
                    ),
                    accessibilityLabel: metricAccessibilityLabel(
                        effort: effort,
                        sideMode: sideMode,
                        metric: effort.targetKind == .duration ? "时长" : "次数"
                    ),
                    unit: effort.targetKind == .duration ? "秒" : "次",
                    decimal: false,
                    validRange: effort.targetKind == .duration
                        ? 1 ... 86400
                        : 1 ... 1000
                )
                WorkoutNumericField(
                    text: weightBinding(
                        groupIDs: groupIDs,
                        effortIndex: effortIndex
                    ),
                    accessibilityLabel: metricAccessibilityLabel(
                        effort: effort,
                        sideMode: sideMode,
                        metric: "外部重量"
                    ),
                    unit: "kg",
                    decimal: true,
                    emptyPrompt: effort.externalWeightKG == 0 ? "自重" : "—",
                    validRange: 0 ... 1000
                )
            } else {
                Text(targetText(effort))
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(weightText(effort.externalWeightKG))
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 48)
    }

    private func restRow(
        _ label: String,
        groupIDs: Set<UUID>,
        effortIndex: Int,
        value: Int?,
        fallbackValue: Int?
    ) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 0.5)
            if isEditable {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WorkoutNumericField(
                    text: intBinding(
                        groupIDs: groupIDs,
                        effortIndex: effortIndex,
                        keyPath: \.restSeconds,
                        fallbackValue: fallbackValue
                    ),
                    accessibilityLabel: label,
                    unit: "秒",
                    decimal: false,
                    compact: true,
                    validRange: 0 ... 3600
                )
            } else if let value {
                Text("\(label) \(value) 秒")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 0.5)
        }
        .frame(minHeight: 28)
    }

    private func workoutChip(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    private func shouldShowRest(
        _ restSeconds: Int?,
        effortIndex: Int,
        effortCount: Int,
        hasTargets: Bool
    ) -> Bool {
        hasTargets && (isEditable || restSeconds != nil
            || (effortIndex == effortCount - 1 && fallbackRestSeconds != nil))
    }

    private func storedRest(
        in run: WorkoutLogicalGroupRun,
        groupIDs: Set<UUID>,
        effortIndex: Int
    ) -> Int? {
        run.groups
            .sorted { $0.sourceOrder < $1.sourceOrder }
            .lazy
            .filter { groupIDs.contains($0.id) }
            .compactMap { group in
                guard group.efforts.indices.contains(effortIndex) else { return nil }
                return group.efforts[effortIndex].restSeconds
            }
            .first
    }

    private func restLabel(
        at effortIndex: Int,
        effortCount: Int,
        sideMode: WorkoutRecordSideMode
    ) -> String {
        guard sideMode == .alternating else { return "间歇" }
        return effortIndex < effortCount - 1 ? "换侧间歇" : "组间歇"
    }

    private func sideLabel(
        _ side: WorkoutEffortSide?,
        mode: WorkoutRecordSideMode
    ) -> String {
        switch side {
        case .some(.left): "左"
        case .some(.right): "右"
        case nil, .some(.none):
            mode == .leftOnly ? "左" : mode == .rightOnly ? "右" : ""
        }
    }

    private func metricAccessibilityLabel(
        effort: WorkoutEffortDraft,
        sideMode: WorkoutRecordSideMode,
        metric: String
    ) -> String {
        let side = sideLabel(effort.side, mode: sideMode)
        return side.isEmpty ? metric : "\(side)侧\(metric)"
    }

    private func targetText(_ effort: WorkoutEffortDraft) -> String {
        switch effort.targetKind {
        case .repetitions:
            effort.reps.map { "\($0) 次" } ?? "— 次"
        case .duration:
            effort.durationSeconds.map { "\($0) 秒" } ?? "— 秒"
        }
    }

    private func weightText(_ value: Double?) -> String {
        guard let value else { return "— kg" }
        return value == 0 ? "自重" : "\(value.formatted()) kg"
    }

    private func intBinding(
        groupIDs: Set<UUID>,
        effortIndex: Int,
        keyPath: WritableKeyPath<WorkoutEffortDraft, Int?>,
        fallbackValue: Int? = nil
    ) -> Binding<String> {
        Binding(
            get: {
                guard let group = draft.groups.first(where: { groupIDs.contains($0.id) }),
                      group.efforts.indices.contains(effortIndex),
                      let value = group.efforts[effortIndex][keyPath: keyPath]
                      ?? fallbackValue
                else {
                    return ""
                }
                return String(value)
            },
            set: { text in
                let value = Int(text)
                draft.updateEffortValue(
                    in: groupIDs,
                    effortIndex: effortIndex,
                    keyPath: keyPath,
                    value: value
                )
            }
        )
    }

    private func weightBinding(
        groupIDs: Set<UUID>,
        effortIndex: Int
    ) -> Binding<String> {
        Binding(
            get: {
                guard let group = draft.groups.first(where: { groupIDs.contains($0.id) }),
                      group.efforts.indices.contains(effortIndex),
                      let value = group.efforts[effortIndex].externalWeightKG,
                      value != 0
                else {
                    return ""
                }
                return value.formatted()
            },
            set: { text in
                let value = Double(text)
                draft.updateEffortValue(
                    in: groupIDs,
                    effortIndex: effortIndex,
                    keyPath: \.externalWeightKG,
                    value: value
                )
            }
        )
    }
}

private struct WorkoutNumericField: View {
    @Binding var text: String
    let accessibilityLabel: String
    let unit: String
    let decimal: Bool
    var emptyPrompt = "—"
    var compact = false
    let validRange: ClosedRange<Double>
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                TextField(
                    accessibilityLabel,
                    text: $text,
                    prompt: Text(emptyPrompt)
                )
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(.subheadline.monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($focused)
                .frame(minWidth: compact ? 32 : 50)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(
                    isInvalid ? "请修改为\(rangeDescription)" : ""
                )
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, compact ? 6 : 9)
            .frame(minHeight: AppTheme.minimumTapTarget)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isInvalid ? AppTheme.destructive : focused ? AppTheme.tint : AppTheme.separator,
                        lineWidth: focused || isInvalid ? 1.5 : 0.5
                    )
            }
            if isInvalid {
                Text("请输入\(rangeDescription)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isInvalid: Bool {
        guard !text.isEmpty else { return false }
        guard let value = decimal ? Double(text) : Int(text).map(Double.init) else {
            return true
        }
        return !validRange.contains(value)
    }

    private var rangeDescription: String {
        let lower = validRange.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let upper = validRange.upperBound.formatted(.number.precision(.fractionLength(0)))
        return "\(lower)–\(upper) \(unit)"
    }

    private var accessibilityValue: String {
        if isInvalid {
            return "输入无效，\(rangeDescription)"
        }
        return text.isEmpty ? "未记录" : "\(text) \(unit)"
    }
}
