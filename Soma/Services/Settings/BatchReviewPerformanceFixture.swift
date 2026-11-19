import CoreData
import QuartzCore
import SwiftData
import UIKit

/// Isolated UI performance scenario. Exercise the production recorder, real reply cards and both root tabs.
@MainActor
enum BatchReviewPerformanceFixture {
    static func start(session: ConversationSession?, context: ModelContext, select: @escaping (AppTab) -> Void) {
        let env = ProcessInfo.processInfo.environment
        guard AppTestRuntime.isRunning, let mode = env["SOMA_UI_BATCH_REVIEW"], ["workout", "meal"].contains(mode),
              context.container.configurations.allSatisfy(\.isStoredInMemoryOnly), let session else { return }
        let count = min(20, max(0, Int(env["SOMA_UI_BATCH_COUNT"] ?? "5") ?? 5))
        Task { @MainActor in
            do {
                let ids = try (0 ..< count).map { index in
                    let definition = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "性能样例动作\(index)", in: context)
                    guard let id = definition.businessID else { throw CocoaError(.validationMissingMandatoryProperty) }
                    return id
                }
                try context.save()
                // Warm both destinations so the post-batch samples exclude their first launch.
                for tab in [AppTab.insights, .settings, .coach] {
                    select(tab)
                    try await Task.sleep(for: .seconds(2))
                }
                let probe = BatchReviewFrameProbe()
                probe.start()
                defer { probe.stop() }
                let turn = UUID()
                let now = Date.now
                let calls: [AgentToolCall] = if count == 0 {
                    []
                } else if mode == "workout" {
                    [.init(name: .createWorkout, arguments: .init(workouts: ids.enumerated().map { workout(id: $0.element, index: $0.offset) }))]
                } else {
                    ids.map { .init(name: .createMeal, arguments: .init(title: "样例饮食\($0)", calories: 100)) }
                }
                let clock = CACurrentMediaTime()
                let results = calls.map {
                    ConversationRecorder.executeAgentTool($0, sourceText: "虚构性能样例", sourceDate: now,
                                                          sourceSessionID: session.id, sourceTurnID: turn,
                                                          mediaKind: .none, mediaPath: nil, in: context)
                }
                guard results.allSatisfy(\.ok), results.flatMap({ $0.recordRefs ?? [] }).count == count else {
                    print("SomaBatchProbe invalid result")
                    return
                }
                print("SomaBatchProbe mode=\(mode) count=\(count) write_ms=\(Int((CACurrentMediaTime() - clock) * 1000))")
                context.insert(CoachMessage(date: now, sessionID: session.id, isFromCoach: false, text: "记录样例", turnID: turn))
                let showsCards = env["SOMA_UI_BATCH_HIDE_REVIEW"] != "1"
                let items = results.enumerated().map { index, original in
                    var result = original
                    if !showsCards {
                        result.recordRefs = []
                    }
                    return AgentTurnItem(sequence: index + 1, kind: .tool, status: .succeeded, title: "记录样例",
                                         startedAt: now, endedAt: now, output: AgentTraceText.json(result))
                }
                context.insert(CoachMessage(date: now.addingTimeInterval(0.01), sessionID: session.id, isFromCoach: true,
                                            text: "已记录。", agentStatus: .succeeded, agentTurnItems: items, turnID: turn))
                try context.save()
                try await Task.sleep(for: .seconds(2))
                probe.report("write_and_present")
                for (label, tab) in [("open_progress", AppTab.insights), ("open_settings", .settings), ("reopen_coach", .coach)] {
                    select(tab)
                    try await Task.sleep(for: .seconds(2))
                    probe.report(label)
                    if tab != .coach {
                        try await Task.sleep(for: .seconds(5))
                        probe.report("\(label)_settled")
                    }
                }
                NotificationCenter.default.post(name: .coachDoubleReselected, object: nil)
                try await Task.sleep(for: .seconds(1))
                probe.report("scroll_to_tail")
                print("SomaBatchProbe finished")
            } catch {
                print("SomaBatchProbe fixture failed")
            }
        }
    }

    private static func workout(id: Int64, index: Int) -> AgentWorkoutCreateInput {
        let shape = index % 5
        let weights: [Double] = switch shape {
        case 0: [14, 14]
        case 1: [6, 12, 17, 13]
        case 2: [32, 45, 52, 63, 63, 63, 63]
        case 3: [8, 16, 24, 18]
        default: [11, 11, 11]
        }
        let sides: [WorkoutEffortSide] = shape == 1 ? [.left, .right] : [.none]
        let efforts = weights.enumerated().flatMap { group, weight in
            sides.map { side in
                AgentWorkoutSetInput(
                    logicalSetIndex: group + 1, side: side, targetKind: .repetitions,
                    reps: shape == 2 && (3 ... 4).contains(group) ? group + 3 : 8,
                    externalWeightKG: weight, restSeconds: shape == 2 ? 150 : 45
                )
            }
        }
        return .init(exerciseID: id, targetKind: .repetitions, laterality: shape == 1 ? .both : ExerciseLaterality.none, setEntries: efforts)
    }
}

@MainActor
private final class BatchReviewFrameProbe: NSObject {
    private var link: CADisplayLink?
    private var last = 0.0
    private var gaps: [Double] = []

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        self.link = link
        last = CACurrentMediaTime()
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        gaps.append((now - last) * 1000)
        last = now
    }

    func report(_ phase: String) {
        let longest = Int(gaps.max() ?? 0)
        print("SomaBatchProbe phase=\(phase) callbacks=\(gaps.count) max_gap_ms=\(longest) gaps_over_100ms=\(gaps.filter { $0 >= 100 }.count)")
        gaps.removeAll(keepingCapacity: true)
        last = CACurrentMediaTime()
    }

    func stop() {
        link?.invalidate()
    }
}
