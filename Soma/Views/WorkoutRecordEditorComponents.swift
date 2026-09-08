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

    private var resolvedFallbackRest: Int? {
        WorkoutRestPropagation.recorded(fallbackRestSeconds)
    }

    private var groupsAreUniform: Bool {
        runs.count <= 1
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
                VStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { position, run in
                        logicalGroupCard(run, position: position)
                        if !groupsAreUniform {
                            afterGroupRest(run, surface: AppTheme.cardBackground)
                        }
                    }
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

            if !dynamicTypeSize.isAccessibilitySize,
               let effort = group.efforts.first,
               effortCount == 1
            {
                if isEditable {
                    compactEditableRun(
                        run,
                        effort: effort,
                        representativeGroupID: group.id,
                        groupIDs: groupIDs
                    )
                } else {
                    compactRecordRun(run, effort: effort)
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
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
                                    ? resolvedFallbackRest
                                    : nil)
                            effortRow(
                                group.efforts[effortIndex],
                                groupIDs: groupIDs,
                                effortIndex: effortIndex,
                                sideMode: group.sideMode,
                                compactRunCount: nil,
                                representativeGroupID: group.id
                            )

                            let restLabel = restLabel(
                                at: effortIndex,
                                effortCount: effortCount,
                                sideMode: group.sideMode
                            )
                            if effortIndex < effortCount - 1 {
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
                                        fallbackValue: displayRest,
                                        surface: AppTheme.insetBackground
                                    )
                                } else {
                                    Divider()
                                        .overlay(AppTheme.separator)
                                }
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

                    if density == .chatCompact {
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
                if groupsAreUniform {
                    afterGroupRest(run, surface: AppTheme.cardBackground)
                }
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
                    .frame(width: 22, alignment: .leading)
                    .accessibilityHidden(true)
            }

            if isEditable {
                WorkoutNumericField(
                    text: effort.targetKind == .duration
                        ? durationBinding(
                            groupIDs: groupIDs,
                            effortIndex: effortIndex
                        )
                        : intBinding(
                            groupIDs: groupIDs,
                            effortIndex: effortIndex,
                            keyPath: \.reps
                        ),
                    accessibilityLabel: metricAccessibilityLabel(
                        effort: effort,
                        sideMode: sideMode,
                        metric: effort.targetKind == .duration ? "时长" : "次数"
                    ),
                    unit: effort.targetKind == .duration ? "" : "次",
                    decimal: false,
                    inline: true,
                    parsesDuration: effort.targetKind == .duration,
                    validRange: effort.targetKind == .duration
                        ? 1 ... 86400
                        : 1 ... 1000
                )
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    unit: effort.externalWeightKG == 0 ? "" : "kg",
                    decimal: true,
                    emptyPrompt: effort.externalWeightKG == 0 ? "自重" : "—",
                    inline: true,
                    validRange: 0 ... 1000
                )
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func afterGroupRest(_ run: WorkoutLogicalGroupRun, surface: Color) -> some View {
        let effortCount = max(run.representative.efforts.count, 1)
        let restGroupIDs = run.restTargetGroupIDs(
            effortIndex: effortCount - 1,
            effortCount: effortCount,
            finalGroupID: draft.finalGroupID
        )
        let evidenceRest = storedRest(
            in: run,
            groupIDs: restGroupIDs,
            effortIndex: effortCount - 1
        )
        let displayRest = evidenceRest ?? resolvedFallbackRest
        let label = restLabel(
            at: effortCount - 1,
            effortCount: effortCount,
            sideMode: run.representative.sideMode
        )
        return Group {
            if shouldShowRest(
                evidenceRest,
                effortIndex: effortCount - 1,
                effortCount: effortCount,
                hasTargets: !restGroupIDs.isEmpty
            ) {
                restRow(
                    label,
                    groupIDs: restGroupIDs,
                    effortIndex: effortCount - 1,
                    value: displayRest,
                    fallbackValue: displayRest,
                    surface: surface
                )
            }
        }
    }

    private func restRow(
        _ label: String,
        groupIDs: Set<UUID>,
        effortIndex: Int,
        value: Int?,
        fallbackValue: Int?,
        surface: Color
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 0.5)
            Group {
                if isEditable {
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
                        prefix: label,
                        inline: true,
                        validRange: 0 ... 3600
                    )
                } else if let value {
                    Text("\(label) \(value) 秒")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .background(surface)
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
            || (effortIndex == effortCount - 1 && resolvedFallbackRest != nil))
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
                return WorkoutRestPropagation.recorded(
                    group.efforts[effortIndex].restSeconds
                )
            }
            .first
    }

    private struct InlineRest {
        let ids: Set<UUID>
        let display: Int?
    }

    private func inlineRest(for run: WorkoutLogicalGroupRun) -> InlineRest? {
        guard groupsAreUniform else {
            return nil
        }
        let ids = run.restTargetGroupIDs(
            effortIndex: 0,
            effortCount: 1,
            finalGroupID: draft.finalGroupID
        )
        guard !ids.isEmpty else {
            return nil
        }
        let evidence = storedRest(in: run, groupIDs: ids, effortIndex: 0)
        guard shouldShowRest(
            evidence,
            effortIndex: 0,
            effortCount: 1,
            hasTargets: true
        ) else {
            return nil
        }
        return InlineRest(ids: ids, display: evidence ?? resolvedFallbackRest)
    }

    private func inlineRestText(for run: WorkoutLogicalGroupRun) -> String? {
        inlineRest(for: run)?.display.map { "间歇 \($0) 秒" }
    }

    private func compactRecordRun(
        _ run: WorkoutLogicalGroupRun,
        effort: WorkoutEffortDraft
    ) -> some View {
        WorkoutCompactRecordRunView(
            target: targetText(effort),
            weight: weightText(effort.externalWeightKG),
            rest: inlineRestText(for: run),
            runCount: run.count
        )
    }

    private func compactEditableRun(
        _ run: WorkoutLogicalGroupRun,
        effort: WorkoutEffortDraft,
        representativeGroupID: UUID,
        groupIDs: Set<UUID>
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                WorkoutNumericField(
                    text: effort.targetKind == .duration
                        ? durationBinding(groupIDs: groupIDs, effortIndex: 0)
                        : intBinding(
                            groupIDs: groupIDs,
                            effortIndex: 0,
                            keyPath: \.reps
                        ),
                    accessibilityLabel: effort.targetKind == .duration ? "时长" : "次数",
                    unit: effort.targetKind == .duration ? "" : "次",
                    decimal: false,
                    inline: true,
                    parsesDuration: effort.targetKind == .duration,
                    validRange: effort.targetKind == .duration
                        ? 1 ... 86400
                        : 1 ... 1000
                )
                WorkoutCompactMetricDivider()
                WorkoutNumericField(
                    text: weightBinding(groupIDs: groupIDs, effortIndex: 0),
                    accessibilityLabel: "外部重量",
                    unit: effort.externalWeightKG == 0 ? "" : "kg",
                    decimal: true,
                    emptyPrompt: effort.externalWeightKG == 0 ? "自重" : "—",
                    inline: true,
                    validRange: 0 ... 1000
                )
                if groupsAreUniform, let rest = inlineRest(for: run) {
                    WorkoutCompactMetricDivider()
                    WorkoutNumericField(
                        text: intBinding(
                            groupIDs: rest.ids,
                            effortIndex: 0,
                            keyPath: \.restSeconds,
                            fallbackValue: rest.display
                        ),
                        accessibilityLabel: "间歇",
                        unit: "秒",
                        decimal: false,
                        prefix: "间歇",
                        inline: true,
                        validRange: 0 ... 3600
                    )
                }
            }
            Spacer(minLength: 8)
            WorkoutRunCountLabel(count: run.count)
            groupMenu(
                representativeGroupID: representativeGroupID,
                groupIDs: groupIDs,
                runCount: run.count
            )
        }
        .padding(.horizontal, 14)
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
            effort.durationSeconds.map(DurationSecondsFormat.display) ?? "—"
        }
    }

    private func weightText(_ value: Double?) -> String {
        guard let value else { return "— kg" }
        return value == 0 ? "自重" : "\(value.formatted()) kg"
    }

    private func durationBinding(
        groupIDs: Set<UUID>,
        effortIndex: Int
    ) -> Binding<String> {
        Binding(
            get: {
                guard let group = draft.groups.first(where: { groupIDs.contains($0.id) }),
                      group.efforts.indices.contains(effortIndex),
                      let value = group.efforts[effortIndex].durationSeconds
                else {
                    return ""
                }
                return DurationSecondsFormat.display(value)
            },
            set: { text in
                draft.updateEffortValue(
                    in: groupIDs,
                    effortIndex: effortIndex,
                    keyPath: \.durationSeconds,
                    value: DurationSecondsFormat.parse(text)
                )
            }
        )
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
                      group.efforts.indices.contains(effortIndex)
                else {
                    return ""
                }
                let stored = group.efforts[effortIndex][keyPath: keyPath]
                let value = keyPath == \.restSeconds
                    ? (WorkoutRestPropagation.recorded(stored) ?? fallbackValue)
                    : (stored ?? fallbackValue)
                guard let value else {
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
