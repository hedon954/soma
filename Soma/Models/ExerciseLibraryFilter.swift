import Foundation

/// Browsing facets derive from current editable facts; they never rewrite exercise metadata.
struct ExerciseLibraryClassification: Equatable {
    static let unspecified = "未标注"
    let name: String
    let primary: Set<String>
    let secondary: Set<String>
    let patterns: Set<String>
    let kinds: Set<ExerciseMovementKind>
    let regions: Set<ExerciseBodyRegion>

    init(name: String, primary: [String], secondary: [String], patterns: [String]) {
        self.name = name
        self.primary = Self.cleaned(primary)
        self.secondary = Self.cleaned(secondary)
        self.patterns = Self.cleaned(patterns)
        let mappedKinds = Set(self.patterns.map(ExerciseMovementKind.resolve))
            .subtracting([.unclassified])
        kinds = mappedKinds.isEmpty ? [.unclassified] : mappedKinds
        let mapped = Set(self.primary.compactMap(ExerciseBodyRegion.resolve))
        regions = mapped.isEmpty ? [.unclassified] : mapped
    }

    private static func cleaned(_ values: [String]) -> Set<String> {
        Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}

enum ExerciseMovementKind: String, CaseIterable, Identifiable {
    case compound = "复合力量"
    case isolation = "孤立训练"
    case core = "核心"
    case power = "爆发表现"
    case cardio = "有氧体能"
    case unclassified = "未标注"

    var id: String {
        rawValue
    }

    static func resolve(_ pattern: String) -> Self {
        switch pattern.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "蹲", "单腿蹲", "弓步", "髋铰链", "水平推", "垂直推", "水平拉", "垂直拉",
             "负重行走", "全身", "臀桥", "拉", "单腿":
            .compound
        case "爆发", "三关节伸展":
            .power
        case "体能":
            .cardio
        case "躯干屈曲", "旋转", "抗旋转", "抗伸展", "核心稳定", "核心":
            .core
        case "膝伸", "膝屈", "髋伸", "髋屈", "髋外展", "髋内收", "肘伸", "肘屈",
             "肩外展", "肩前屈", "肩伸展", "跖屈", "腕屈伸", "肩胛后缩", "肩胛上提",
             "水平内收", "水平外展", "器械孤立", "手臂孤立", "肩部孤立", "胸部孤立",
             "背部孤立", "小腿孤立", "前臂孤立", "前臂", "握力", "颈屈伸":
            .isolation
        default:
            .unclassified
        }
    }
}

enum ExerciseBodyRegion: String, CaseIterable, Identifiable {
    case chest = "胸部"
    case back = "背部"
    case shoulders = "肩部"
    case arms = "手臂"
    case core = "核心"
    case glutes = "臀部"
    case legs = "腿部"
    case neck = "颈部"
    case unclassified = "未标注"

    var id: String {
        rawValue
    }

    static func resolve(_ muscle: String) -> Self? {
        // Keep exact anatomical muscle labels in the muscle facet. The map's coarser
        // aliases are used only for the body-region facet.
        if let group = MuscleGroupMapping.resolveOne(muscle) {
            switch group {
            case .chest: return .chest
            case .trapezius, .upperBack, .lowerBack: return .back
            case .frontDeltoids, .backDeltoids: return .shoulders
            case .biceps, .triceps, .forearm: return .arms
            case .abs, .obliques: return .core
            case .gluteal, .abductors: return .glutes
            case .adductors, .hamstring, .quadriceps, .calves: return .legs
            case .neck: return .neck
            }
        }
        switch muscle {
        case "胸大肌上部", "胸大肌下部", "胸小肌": return .chest
        case "菱形肌", "斜方肌中束", "斜方肌下束", "斜方肌中下束": return .back
        case "冈上肌", "冈下肌", "小圆肌", "肩袖": return .shoulders
        case "肱肌", "肱桡肌": return .arms
        case "腹横肌": return .core
        case "髋屈肌", "髂腰肌", "胫骨前肌": return .legs
        default: return nil
        }
    }
}

struct ExerciseLibraryFilter: Equatable {
    var region: ExerciseBodyRegion?
    var pattern: String?
    var muscle: String?
    var primaryOnly = false

    var count: Int {
        [region != nil, pattern != nil, muscle != nil].filter { $0 }.count
    }

    func matches(_ item: ExerciseLibraryClassification, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || item.name.localizedCaseInsensitiveContains(query) else { return false }
        if let region, !item.regions.contains(region) {
            return false
        }
        if let pattern {
            let kinds = Set(item.kinds.map(\.rawValue))
            if !matches(pattern, values: kinds) {
                return false
            }
        }
        let muscles = primaryOnly ? item.primary : item.primary.union(item.secondary)
        if let muscle, !matches(muscle, values: muscles) {
            return false
        }
        return true
    }

    private func matches(_ selection: String, values: Set<String>) -> Bool {
        values.contains(selection)
    }
}
