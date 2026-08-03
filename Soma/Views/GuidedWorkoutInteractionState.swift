import Foundation

enum GuidedWorkoutPresentationMode: Equatable {
    case compact
    case expandedCapture
}

struct GuidedWorkoutPresentationState: Equatable {
    private(set) var mode = GuidedWorkoutPresentationMode.compact

    init(mode: GuidedWorkoutPresentationMode = .compact) {
        self.mode = mode
    }

    mutating func expand() {
        mode = .expandedCapture
    }

    mutating func collapse() {
        mode = .compact
    }

    mutating func cameraStateChanged(_ state: WorkoutCameraState) {
        if state == .recording {
            mode = .expandedCapture
        }
    }

    mutating func phaseChanged(_ phase: GuidedWorkoutPhase) {
        if phase != .setInProgress {
            mode = .compact
        }
    }
}

struct GuidedSetCountdownClock: Equatable {
    static let duration: TimeInterval = 3

    let startedAt: Date

    var deadline: Date {
        startedAt.addingTimeInterval(Self.duration)
    }

    func remaining(at date: Date) -> Int {
        max(Int(ceil(deadline.timeIntervalSince(date))), 0)
    }

    func delay(at date: Date) -> TimeInterval {
        max(deadline.timeIntervalSince(date), 0)
    }

    func isDue(at date: Date) -> Bool {
        date >= deadline
    }
}
