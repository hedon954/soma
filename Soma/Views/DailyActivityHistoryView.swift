import SwiftData
import SwiftUI

/// 独立日常活动历史入口；不进入训练列表（ADR 0146）。
struct DailyActivityHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var loaded: [WorkoutEntry] = []
    @State private var hasMore = true
    @State private var isLoading = false

    private let pageSize = 40

    var body: some View {
        List {
            if loaded.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无日常活动",
                    systemImage: "figure.walk",
                    description: Text("连接 Apple 健康并同步后，每日步数会出现在这里。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(loaded, id: \.id) { workout in
                    NavigationLink {
                        DailyActivityRecordDetailView(workout: workout)
                    } label: {
                        DailyActivityHistoryRow(workout: workout)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
                if hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 12)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { loadMore() }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("日常活动")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if loaded.isEmpty {
                reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            guard ModelContextSaveImpact.affectsInsights(notification, in: modelContext) else { return }
            reload()
        }
    }

    private func reload() {
        loaded = []
        hasMore = true
        isLoading = false
        loadMore()
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { workout in
                workout.externalSource == "appleHealth" || workout.externalSource == "coros"
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize + 1
        descriptor.fetchOffset = loaded.count
        do {
            let rows = try modelContext.fetch(descriptor).filter(\.isDailyActivity)
            loaded.append(contentsOf: Array(rows.prefix(pageSize)))
            hasMore = rows.count > pageSize
        } catch {
            hasMore = false
        }
    }
}

private struct DailyActivityHistoryRow: View {
    let workout: WorkoutEntry

    var body: some View {
        HStack(spacing: 12) {
            DailyActivitySourceIcon(kind: .winning(workout.dailyActivityWinningSource), size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                if let summary = workout.dailyActivitySummary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daily-activity-history-row")
    }
}
