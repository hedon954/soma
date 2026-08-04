import Foundation

/// Canonical muscle keys used for programmatic highlighting.
/// Free-text `primaryMuscles` / `secondaryMuscles` remain the editable facts;
/// rendering maps those strings through `MuscleGroupMapping`.
enum MuscleGroup: String, CaseIterable, Codable, Sendable, Hashable {
    case trapezius
    case upperBack = "upper-back"
    case lowerBack = "lower-back"
    case chest
    case biceps
    case triceps
    case forearm
    case backDeltoids = "back-deltoids"
    case frontDeltoids = "front-deltoids"
    case abs
    case obliques
    case adductors = "adductor"
    case abductors
    case hamstring
    case quadriceps
    case calves
    case gluteal
    case neck

    var displayName: String {
        switch self {
        case .trapezius: "斜方肌"
        case .upperBack: "上背"
        case .lowerBack: "下背"
        case .chest: "胸大肌"
        case .biceps: "肱二头肌"
        case .triceps: "肱三头肌"
        case .forearm: "前臂"
        case .backDeltoids: "三角肌后束"
        case .frontDeltoids: "三角肌前束"
        case .abs: "腹直肌"
        case .obliques: "腹斜肌"
        case .adductors: "内收肌"
        case .abductors: "外展肌"
        case .hamstring: "腘绳肌"
        case .quadriceps: "股四头肌"
        case .calves: "小腿"
        case .gluteal: "臀大肌"
        case .neck: "颈部"
        }
    }

    var side: MuscleMapSide {
        switch self {
        case .trapezius, .upperBack, .lowerBack, .triceps, .backDeltoids,
             .hamstring, .gluteal, .calves:
            .posterior
        case .chest, .biceps, .forearm, .frontDeltoids, .abs, .obliques,
             .adductors, .abductors, .quadriceps, .neck:
            .anterior
        }
    }

    /// Some groups appear on both body views in the path dataset.
    var pathKeys: [String] {
        switch self {
        case .calves:
            ["calves", "tibialis", "left-soleus", "right-soleus"]
        case .frontDeltoids:
            ["front-deltoids", "deltoids"]
        case .backDeltoids:
            ["back-deltoids", "deltoids"]
        case .adductors:
            ["adductor", "adductors"]
        default:
            [rawValue]
        }
    }

    /// Resolves a path slug from the SVG dataset into a muscle group.
    static func group(forPathKey key: String, side: MuscleMapSide) -> MuscleGroup? {
        switch key {
        case "deltoids":
            return side == .anterior ? .frontDeltoids : .backDeltoids
        case "tibialis", "left-soleus", "right-soleus":
            return .calves
        case "adductors":
            return .adductors
        default:
            if let exact = MuscleGroup(rawValue: key) {
                return exact
            }
            return allCases.first { $0.pathKeys.contains(key) }
        }
    }
}

enum MuscleGroupMapping {
    /// Deterministic Chinese/alias → canonical muscle mapping. Unmapped names stay dark.
    static func resolve(_ rawNames: [String]) -> Set<MuscleGroup> {
        Set(rawNames.compactMap(resolveOne))
    }

    static func resolveOne(_ raw: String) -> MuscleGroup? {
        let key = normalize(raw)
        guard !key.isEmpty else { return nil }
        return aliases[key]
    }

    static func intensityMap(
        primary: [String],
        secondary: [String],
        primaryWeight: Double = 1.0,
        secondaryWeight: Double = 0.45
    ) -> [MuscleGroup: Double] {
        var values: [MuscleGroup: Double] = [:]
        for group in resolve(primary) {
            values[group, default: 0] += primaryWeight
        }
        for group in resolve(secondary) {
            values[group, default: 0] += secondaryWeight
        }
        return values
    }

    static func merge(
        _ maps: [[MuscleGroup: Double]]
    ) -> [MuscleGroup: Double] {
        var values: [MuscleGroup: Double] = [:]
        for map in maps {
            for (group, score) in map {
                values[group, default: 0] += score
            }
        }
        return values
    }

    static func normalized(
        _ values: [MuscleGroup: Double]
    ) -> [MuscleGroup: Double] {
        guard let maxValue = values.values.max(), maxValue > 0 else {
            return [:]
        }
        return values.mapValues { min(1, $0 / maxValue) }
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
    }

    private static let aliases: [String: MuscleGroup] = {
        var map: [String: MuscleGroup] = [:]
        func add(_ names: [String], _ group: MuscleGroup) {
            for name in names {
                map[normalize(name)] = group
            }
        }

        add(["斜方肌", "trapezius", "traps"], .trapezius)
        add(["上背", "背阔肌", "lat", "lats", "latissimus", "upper-back", "upperback"], .upperBack)
        add(["下背", "竖脊肌", "lower-back", "lowerback", "erectors"], .lowerBack)
        add(["胸大肌", "胸", "胸部", "chest", "pectoral", "pecs"], .chest)
        add(["肱二头肌", "二头肌", "biceps"], .biceps)
        add(["肱三头肌", "三头肌", "triceps"], .triceps)
        add(["前臂", "前臂肌群", "forearm", "forearms"], .forearm)
        add(["三角肌后束", "后束", "后肩", "rear delt", "rear deltoid", "back-deltoids"], .backDeltoids)
        add(
            ["三角肌前束", "前束", "前肩", "三角肌中束", "中束", "三角肌", "肩", "肩部",
             "front delt", "front deltoid", "deltoid", "shoulders", "front-deltoids"],
            .frontDeltoids
        )
        add(["腹直肌", "腹肌", "核心", "abs", "abdomen", "core"], .abs)
        add(["腹斜肌", "obliques"], .obliques)
        add(["内收肌", "大腿内侧", "adductor", "adductors"], .adductors)
        add(["外展肌", "臀中肌", "abductors", "glute med"], .abductors)
        add(["腘绳肌", "腿后侧", "腘绳", "hamstring", "hamstrings"], .hamstring)
        add(["股四头肌", "腿前侧", "quad", "quads", "quadriceps"], .quadriceps)
        add(["小腿", "腓肠肌", "比目鱼肌", "calves", "calf", "soleus"], .calves)
        add(["臀大肌", "臀部", "臀", "glute", "glutes", "gluteal"], .gluteal)
        add(["颈部", "颈", "neck"], .neck)
        return map
    }()
}
