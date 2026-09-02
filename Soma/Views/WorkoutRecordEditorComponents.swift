import SwiftUI

enum WorkoutRecordEditorDensity {
    case standard
    case chatCompact
}

struct WorkoutLogicalGroupsEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var draft: WorkoutRecordDraft
    let isEditable: Bool
    var fallbackRestSeconds: Int?
    var density: WorkoutRecordEditorDensity = .standard
    var showsAddButton = true

    private var runs: [WorkoutLogicalGroupRun] {
        draft.displayRuns
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: density == .chatCompact ? 8 : AppTheme.groupSpacing
        ) {
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

            if isEditable, showsAddButton {
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

        return VStack(
            alignment: .leading,
            spacing: density == .chatCompact ? 6 : 10
        ) {
            if density == .standard {
                HStack(spacing: 8) {
                    workoutChip(group.targetKindLabel)
                    workoutChip(draft.sideLabel(for: group))
                    Spacer(minLength: 6)
                    WorkoutRunCountLabel(count: run.count)
                    if isEditable {
                        groupMenu(
                            representativeGroupID: group.id,
                            groupIDs: groupIDs,
                            runCount: run.count
                        )
                    }
                }
            }

            if density == .chatCompact,
               !dynamicTypeSize.isAccessibilitySize,
               let effort = group.efforts.first,
               effortCount == 1
            {
                if isEditable {
                    compactEditableRun(
                        run,
                        effort: effort,
                        representativeGroupID: group.id,
                        groupIDs: groupIDs,
                        finalGroupID: draft.finalGroupID
                    )
                } else {
                    compactRecordRun(
                        run,
                        effort: effort,
                        finalGroupID: draft.finalGroupID
                    )
                }
            } else {
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
                            ?? (effortIndex == effortCount - 1
                                ? fallbackRestSeconds
                                : nil)
                        effortRow(
                            group.efforts[effortIndex],
                            groupIDs: groupIDs,
                            effortIndex: effortIndex,
                            sideMode: group.sideMode,
                            compactRunCount: effortIndex == 0 ? run.count : nil,
                            representativeGroupID: group.id
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
                .padding(.horizontal, density == .chatCompact ? 9 : 14)
                .background(
                    AppTheme.insetBackground,
                    in: RoundedRectangle(
                        cornerRadius: AppTheme.controlRadius,
                        style: .continuous
                    )
                )
            }
        }
        .padding(density == .chatCompact ? 0 : 14)
        .background(
            density == .chatCompact ? Color.clear : AppTheme.cardBackground,
            in: RoundedRectangle(
                cornerRadius: AppTheme.cardRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(
                    density == .chatCompact ? Color.clear : AppTheme.separator,
                    lineWidth: 0.5
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "第 \(position + 1) 个逻辑组，\(group.targetKindLabel)，\(draft.sideLabel(for: group))"
        )
    }

    private func effortRow(
        _ effort: WorkoutEffortDraft,
        groupIDs: Set<UUID>,
        effortIndex: Int,
        sideMode: WorkoutRecordSideMode,
        compactRunCount: Int?,
        representativeGroupID: UUID
    ) -> some View {
        HStack(spacing: 10) {
            if sideMode.showsEffortSideLabel {
                Text(sideLabel(effort.side, mode: sideMode))
                    .font(.subheadline.weight(.medium))
                    .frame(width: 34, alignment: .leading)
                    .accessibilityHidden(true)
            }

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
                    flat: density == .chatCompact,
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
                    flat: density == .chatCompact,
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

            if density == .chatCompact, let compactRunCount {
                WorkoutRunCountLabel(count: compactRunCount)
                if isEditable {
                    groupMenu(
                        representativeGroupID: representativeGroupID,
                        groupIDs: groupIDs,
                        runCount: compactRunCount
                    )
                }
            }
        }
        .frame(minHeight: density == .chatCompact ? AppTheme.minimumTapTarget : 48)
    }

    private func groupMenu(
        representativeGroupID: UUID,
        groupIDs: Set<UUID>,
        runCount: Int
    ) -> some View {
        Menu {
            Button {
                draft.appendGroup(copying: representativeGroupID)
            } label: {
                Label("复制这一组", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                for id in groupIDs {
                    draft.removeGroup(id: id)
                }
            } label: {
                Label(
                    runCount > 1 ? "删除这批组" : "删除这一组",
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
            .padding(.horizontal, density == .chatCompact ? 7 : 9)
            .padding(.vertical, density == .chatCompact ? 3 : 5)
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

    private func compactRecordRun(
        _ run: WorkoutLogicalGroupRun,
        effort: WorkoutEffortDraft,
        finalGroupID: UUID?
    ) -> some View {
        let restGroupIDs = run.restTargetGroupIDs(
            effortIndex: 0,
            effortCount: 1,
            finalGroupID: finalGroupID
        )
        let evidenceRest = storedRest(
            in: run,
            groupIDs: restGroupIDs,
            effortIndex: 0
        )
        let displayRest = evidenceRest ?? fallbackRestSeconds
        let showsRest = shouldShowRest(
            evidenceRest,
            effortIndex: 0,
            effortCount: 1,
            hasTargets: !restGroupIDs.isEmpty
        )

        return WorkoutCompactRecordRunView(
            target: targetText(effort),
            weight: weightText(effort.externalWeightKG),
            rest: showsRest ? displayRest.map { "间歇 \($0) 秒" } : nil,
            runCount: run.count
        )
    }

    private func compactEditableRun(
        _ run: WorkoutLogicalGroupRun,
        effort: WorkoutEffortDraft,
        representativeGroupID: UUID,
        groupIDs: Set<UUID>,
        finalGroupID: UUID?
    ) -> some View {
        let restGroupIDs = run.restTargetGroupIDs(
            effortIndex: 0,
            effortCount: 1,
            finalGroupID: finalGroupID
        )
        let evidenceRest = storedRest(
            in: run,
            groupIDs: restGroupIDs,
            effortIndex: 0
        )
        let displayRest = evidenceRest ?? fallbackRestSeconds

        return HStack(spacing: 0) {
            WorkoutNumericField(
                text: intBinding(
                    groupIDs: groupIDs,
                    effortIndex: 0,
                    keyPath: effort.targetKind == .duration
                        ? \.durationSeconds
                        : \.reps
                ),
                accessibilityLabel: effort.targetKind == .duration ? "时长" : "次数",
                unit: effort.targetKind == .duration ? "秒" : "次",
                decimal: false,
                compact: true,
                flat: true,
                validRange: effort.targetKind == .duration
                    ? 1 ... 86400
                    : 1 ... 1000
            )
            .frame(width: 58)
            WorkoutCompactMetricDivider()
            WorkoutNumericField(
                text: weightBinding(groupIDs: groupIDs, effortIndex: 0),
                accessibilityLabel: "外部重量",
                unit: effort.externalWeightKG == 0 ? "" : "kg",
                decimal: true,
                emptyPrompt: effort.externalWeightKG == 0 ? "自重" : "—",
                compact: true,
                flat: true,
                validRange: 0 ... 1000
            )
            .frame(width: 55)
            WorkoutCompactMetricDivider()
            WorkoutCompactGroupCountLabel(count: run.count)
            if !restGroupIDs.isEmpty {
                WorkoutCompactMetricDivider()
                HStack(spacing: 0) {
                    Text("间歇")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    WorkoutNumericField(
                        text: intBinding(
                            groupIDs: restGroupIDs,
                            effortIndex: 0,
                            keyPath: \.restSeconds,
                            fallbackValue: displayRest
                        ),
                        accessibilityLabel: "间歇",
                        unit: "秒",
                        decimal: false,
                        compact: true,
                        flat: true,
                        validRange: 0 ... 3600
                    )
                    .frame(width: 54)
                }
            }
            WorkoutCompactMetricDivider()
            groupMenu(
                representativeGroupID: representativeGroupID,
                groupIDs: groupIDs,
                runCount: run.count
            )
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapTarget)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(
                cornerRadius: AppTheme.controlRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-compact-inline-run")
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
