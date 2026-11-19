import SwiftData
import SwiftUI

extension Notification.Name {
    static let startMealBackfill = Notification.Name("Soma.startMealBackfill")
}

struct MealBackfillView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Query private var meals: [MealEntry]
    @Query private var evidence: [EnergyContextEntry]
    @AppStorage("mealBackfill.hiddenDay") private var hiddenDay = 0.0
    @State private var showsHistory = false
    @State private var expandedDays: [Date: Bool] = [:]
    @State private var undo: MealBackfillTarget?
    @State private var error: String?
    private let day: Date
    private let pastDays: Int
    private let isCoach: Bool
    private let missingExpenditure: Set<Date>

    init(day: Date = .now, pastDays: Int = 3, isCoach: Bool = false, missingExpenditure: Set<Date> = []) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let first = calendar.date(byAdding: .day, value: -pastDays, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let zone = calendar.timeZone.identifier
        self.day = start
        self.pastDays = pastDays
        self.isCoach = isCoach
        self.missingExpenditure = missingExpenditure
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= first && $0.date < end }, sort: \MealEntry.date)
        _evidence = Query(filter: #Predicate<EnergyContextEntry> { $0.date >= first && $0.date < end && $0.timeZoneIdentifier == zone })
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let days = coverage(at: LibraryAndMealTestFixture.reminderTime(timeline.date))
            if isCoach {
                if Calendar.current.isDate(day, inSameDayAs: timeline.date),
                   hiddenDay != day.timeIntervalSinceReferenceDate,
                   !days.isEmpty || undo != nil
                {
                    reminder(days)
                }
            } else {
                List {
                    if let undo {
                        undoButton(undo)
                    }
                    daySections(days)
                    if days.isEmpty {
                        Text("没有待补的餐次")
                    }
                }
            }
        }
        .alert("饮食记录未更新", isPresented: Binding(get: { error != nil }, set: {
            if !$0 {
                error = nil
            }
        })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private struct DayCoverage: Identifiable {
        let date: Date
        let missing: [MealType]
        var id: Date {
            date
        }
    }

    private func coverage(at now: Date) -> [DayCoverage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.date) }
        let evidenceByDay = Dictionary(evidence.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        return (0 ... pastDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day), date <= now else { return nil }
            let entries = (grouped[date] ?? []).filter { $0.date <= now }
            let flags = evidenceByDay[date]
            let legacy = flags?.confirmationData.flatMap { try? JSONDecoder().decode(EnergyDayConfirmation.self, from: $0) }
            let confirmed = !entries.isEmpty && legacy?.foodComplete == true
                && legacy?.mealEvidenceFingerprint == EnergyFoodEvidence.fingerprint(for: entries)
            let skips = (try? MealCoverageStore.skipped(flags)) ?? []
            let present = Set(entries.compactMap { MealType(rawValue: $0.mealTypeRaw) })
            let coverage = MealCoverage(recorded: present, skipped: skips, previouslyConfirmedDay: confirmed)
            let missing = coverage.missing.filter { type in
                !isCoach || MealCoverage.due(type, on: date, now: now, calendar: calendar)
            }
            return !missing.isEmpty || missingExpenditure.contains(date) ? DayCoverage(date: date, missing: missing) : nil
        }
    }

    private func reminder(_ days: [DayCoverage]) -> some View {
        let history = days.filter { $0.date != day }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("补记饮食", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.mealEmphasis)
                Spacer()
                Button {
                    hiddenDay = day.timeIntervalSinceReferenceDate
                } label: {
                    Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("今天先不提醒")
            }
            if let today = days.first(where: { $0.date == day }) {
                dayRows(today)
            }
            if !history.isEmpty {
                Button { showsHistory = true } label: {
                    HStack {
                        Text("过去 \(history.count) 天 · \(history.reduce(0) { $0 + $1.missing.count }) 餐待补")
                        Spacer()
                        Text("查看")
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach-meal-backfill-history")
            }
            if let undo, !showsHistory {
                undoButton(undo)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showsHistory) {
            NavigationStack {
                List {
                    if let undo {
                        undoButton(undo)
                    }
                    daySections(history)
                }
                .navigationTitle("过去几天的饮食")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showsHistory = false } } }
            }
            .presentationDragIndicator(.visible)
        }
    }

    private func daySections(_ days: [DayCoverage]) -> some View {
        ForEach(days) { group in
            let expanded = Binding(
                get: { expandedDays[group.date] ?? (group.id == days.first?.id) },
                set: { expandedDays[group.date] = $0 }
            )
            DisclosureGroup(isExpanded: expanded) {
                dayRows(group)
                if missingExpenditure.contains(group.date) {
                    Text("缺少消耗估算").foregroundStyle(.secondary)
                }
            } label: {
                LabeledContent(group.date.formatted(.dateTime.month().day().weekday()),
                               value: group.missing.isEmpty ? "消耗待估算" : "\(group.missing.count) 餐待补")
            }
        }
    }

    private func dayRows(_ group: DayCoverage) -> some View {
        ForEach(group.missing) { type in
            let target = MealBackfillTarget(day: group.date, meal: type)
            let date = dateLabel(group.date)
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
            layout {
                Text(type.rawValue).font(.subheadline)
                if !textSize.isAccessibilitySize {
                    Spacer()
                }
                HStack {
                    Button {
                        if showsHistory {
                            showsHistory = false
                        }
                        if !isCoach {
                            dismiss()
                        }
                        NotificationCenter.default.post(name: .openCoachConversation, object: nil)
                        NotificationCenter.default.post(name: .startMealBackfill, object: target)
                    } label: {
                        mealActionLabel("记录")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("记录\(date)的\(type.rawValue)")
                    Button {
                        update(target, skipped: true)
                    } label: {
                        mealActionLabel("没吃")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("标记\(date)的\(type.rawValue)没吃")
                }
            }
        }
    }

    private func undoButton(_ target: MealBackfillTarget) -> some View {
        Button {
            update(target, skipped: false)
        } label: {
            mealActionLabel("撤销\(target.meal.rawValue)没吃")
        }
        .accessibilityLabel("撤销\(dateLabel(target.day))的\(target.meal.rawValue)没吃")
    }

    private func mealActionLabel(_ title: String) -> some View {
        Text(title)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func dateLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "今天" : date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }

    private func update(_ target: MealBackfillTarget, skipped: Bool) {
        do {
            try MealCoverageStore.setSkipped(skipped, meal: target.meal, day: target.day, in: context)
            undo = skipped ? target : nil
        } catch {
            self.error = AppErrorMessage.message(for: error, operation: .save)
        }
    }
}
