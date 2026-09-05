import Foundation

/// Browsing facets derive from current editable facts; they never rewrite exercise metadata.
struct ExerciseLibraryClassification: Equatable {
    static let unspecified = "未标注"
    let name: String
    let primary: Set<String>
    let secondary: Set<String>
    let patterns: Set<String>
    let regions: Set<ExerciseBodyRegion>

    init(name: String, primary: [String], secondary: [String], patterns: [String]) {
        self.name = name
        self.primary = Self.cleaned(primary)
        self.secondary = Self.cleaned(secondary)
        self.patterns = Self.cleaned(patterns)
        let mapped = Set(self.primary.compactMap(ExerciseBodyRegion.resolve))
        regions = mapped.isEmpty ? [.unclassified] : mapped
    }

    private static func cleaned(_ values: [String]) -> Set<String> {
        Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
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
        if let pattern, !matches(pattern, values: item.patterns) {
            return false
        }
        let muscles = primaryOnly ? item.primary : item.primary.union(item.secondary)
        if let muscle, !matches(muscle, values: muscles) {
            return false
        }
        return true
    }

    private func matches(_ selection: String, values: Set<String>) -> Bool {
        selection == ExerciseLibraryClassification.unspecified ? values.isEmpty : values.contains(selection)
    }
}
