import SwiftData
import SwiftUI

struct CoachDeviceReadView: View {
    let read: DeviceCoachRead
    let date: Date
    @Environment(\.modelContext) private var context
    @Environment(\.coachTabIsActive) private var isActive
    @State private var result: DeviceCoachReadResult?
    @State private var failure: String?
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                Label(result.title, systemImage: read == .dailyEnergy ? "flame" : "dumbbell")
                    .font(.subheadline.weight(.semibold))
                if !result.details.isEmpty {
                    DisclosureGroup("查看明细") {
                        ForEach(Array(result.details.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.caption)
                }
            } else if let failure {
                Text(failure).font(.subheadline)
                Button("重试") { revision += 1 }.frame(minHeight: 44)
            } else {
                ProgressView("正在读取记录…")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .task(id: Request(isActive: isActive, revision: revision)) {
            guard isActive, result == nil else { return }
            do {
                result = try await read.load(day: date, container: context.container)
            } catch is CancellationError {
                return
            } catch {
                failure = AppErrorMessage.message(for: error, operation: .load)
            }
        }
    }

    private struct Request: Equatable {
        let isActive: Bool
        let revision: Int
    }
}

struct CoachSuggestedReads: View {
    let recordedFood: Bool
    let recordedWorkout: Bool
    let userEndedTraining: Bool
    let date: Date
    let submit: (DeviceCoachRead) async -> Bool
    let onWillReveal: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.coachTabIsActive) private var isActive
    @Environment(InsightsSnapshotRevisionState.self) private var insightsRevision
    @State private var reads: [DeviceCoachRead] = []
    @State private var pending: DeviceCoachRead?
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !submitted, !reads.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack { buttons }
                    VStack(alignment: .leading) { buttons }
                }
            }
        }
        .task(id: AvailabilityRequest(isActive: isActive, revision: insightsRevision.dataRevision)) {
            guard isActive else { return }
            let container = context.container
            async let training = offersTrainingSummary(in: container)
            async let energy = offersEnergyRead(in: container)
            let (showsTraining, showsEnergy) = await (training, energy)
            guard !Task.isCancelled else { return }
            let candidates: [DeviceCoachRead] = [showsTraining ? .trainingSummary : nil, showsEnergy ? .dailyEnergy : nil].compactMap { $0 }
            if candidates.contains(where: { !reads.contains($0) }) {
                onWillReveal()
            }
            reads = candidates
        }
        .task(id: isActive ? pending : nil) {
            guard isActive, let read = pending else { return }
            let accepted = await submit(read)
            guard !Task.isCancelled else { return }
            submitted = accepted
            if !accepted {
                reads.removeAll { $0 == read }
            }
            pending = nil
        }
        .onChange(of: isActive) { _, active in
            if !active {
                pending = nil
            }
        }
    }

    private func offersTrainingSummary(in container: ModelContainer) async -> Bool {
        guard recordedWorkout else { return false }
        if userEndedTraining {
            return await (try? DeviceCoachRead.trainingSummary.load(day: date, container: container))?.isAvailable == true
        }
        let date = date
        let work = Task.detached(priority: .utility) {
            try await TrainingCompletionEvidenceLoader(modelContainer: container).hasUsualCompletedSession(on: date)
        }
        return await withTaskCancellationHandler {
            await (try? work.value) ?? false
        } onCancel: {
            work.cancel()
        }
    }

    private func offersEnergyRead(in container: ModelContainer) async -> Bool {
        guard recordedFood else { return false }
        return await (try? DeviceCoachRead.dailyEnergy.load(day: date, container: container))?.isAvailable == true
    }

    private struct AvailabilityRequest: Equatable {
        let isActive: Bool
        let revision: Int
    }

    private var buttons: some View {
        ForEach(reads, id: \.rawValue) { read in
            Button {
                guard isActive, pending == nil, !submitted, Calendar.current.isDateInToday(date) else { return }
                pending = read
            } label: {
                Text(read.prompt)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pending != nil)
            .accessibilityIdentifier("coach-next-action-\(read.rawValue)")
        }
    }
}
