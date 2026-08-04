import CoreGraphics
import Foundation

enum MuscleMapLabelEdge: String, Sendable, Equatable {
    case leading
    case trailing
}

struct MuscleMapLabelAnchor: Sendable, Equatable {
    var group: MuscleGroup
    var side: MuscleMapSide
    /// Muscle attach point in local view coordinates (0...724 x, 0...1448 y).
    var musclePoint: CGPoint
    /// Vertical label slot in local view coordinates.
    var labelY: CGFloat
    var edge: MuscleMapLabelEdge
}

enum MuscleMapLabels {
    static func anchors(for side: MuscleMapSide) -> [MuscleMapLabelAnchor] {
        switch side {
        case .anterior: anterior
        case .posterior: posterior
        }
    }

    static func coversAllGroups() -> Bool {
        let covered = Set((anterior + posterior).map(\.group))
        return Set(MuscleGroup.allCases).isSubset(of: covered)
    }

    private static let anterior: [MuscleMapLabelAnchor] = [
        .init(group: .neck, side: .anterior,
              musclePoint: CGPoint(x: 362, y: 280), labelY: 250, edge: .leading),
        .init(group: .frontDeltoids, side: .anterior,
              musclePoint: CGPoint(x: 250, y: 370), labelY: 360, edge: .leading),
        .init(group: .chest, side: .anterior,
              musclePoint: CGPoint(x: 330, y: 420), labelY: 430, edge: .leading),
        .init(group: .biceps, side: .anterior,
              musclePoint: CGPoint(x: 200, y: 470), labelY: 500, edge: .leading),
        .init(group: .forearm, side: .anterior,
              musclePoint: CGPoint(x: 160, y: 560), labelY: 580, edge: .leading),
        .init(group: .obliques, side: .anterior,
              musclePoint: CGPoint(x: 290, y: 560), labelY: 650, edge: .leading),
        .init(group: .abs, side: .anterior,
              musclePoint: CGPoint(x: 362, y: 560), labelY: 520, edge: .trailing),
        .init(group: .quadriceps, side: .anterior,
              musclePoint: CGPoint(x: 310, y: 820), labelY: 820, edge: .leading),
        .init(group: .adductors, side: .anterior,
              musclePoint: CGPoint(x: 362, y: 780), labelY: 760, edge: .trailing),
        .init(group: .abductors, side: .anterior,
              musclePoint: CGPoint(x: 250, y: 760), labelY: 700, edge: .trailing),
        .init(group: .calves, side: .anterior,
              musclePoint: CGPoint(x: 300, y: 1100), labelY: 1100, edge: .leading)
    ]

    private static let posterior: [MuscleMapLabelAnchor] = [
        .init(group: .neck, side: .posterior,
              musclePoint: CGPoint(x: 362, y: 280), labelY: 250, edge: .trailing),
        .init(group: .trapezius, side: .posterior,
              musclePoint: CGPoint(x: 362, y: 360), labelY: 340, edge: .trailing),
        .init(group: .backDeltoids, side: .posterior,
              musclePoint: CGPoint(x: 250, y: 390), labelY: 380, edge: .leading),
        .init(group: .upperBack, side: .posterior,
              musclePoint: CGPoint(x: 320, y: 480), labelY: 470, edge: .leading),
        .init(group: .triceps, side: .posterior,
              musclePoint: CGPoint(x: 210, y: 500), labelY: 540, edge: .leading),
        .init(group: .forearm, side: .posterior,
              musclePoint: CGPoint(x: 160, y: 580), labelY: 620, edge: .leading),
        .init(group: .lowerBack, side: .posterior,
              musclePoint: CGPoint(x: 362, y: 620), labelY: 600, edge: .trailing),
        .init(group: .gluteal, side: .posterior,
              musclePoint: CGPoint(x: 340, y: 740), labelY: 740, edge: .trailing),
        .init(group: .hamstring, side: .posterior,
              musclePoint: CGPoint(x: 320, y: 900), labelY: 900, edge: .leading),
        .init(group: .calves, side: .posterior,
              musclePoint: CGPoint(x: 300, y: 1120), labelY: 1120, edge: .leading),
        .init(group: .adductors, side: .posterior,
              musclePoint: CGPoint(x: 362, y: 820), labelY: 860, edge: .trailing),
        .init(group: .abductors, side: .posterior,
              musclePoint: CGPoint(x: 250, y: 780), labelY: 800, edge: .trailing)
    ]
}
