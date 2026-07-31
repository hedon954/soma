import Foundation

struct BundledExerciseContent: Equatable, Sendable {
    var canonicalName: String
    var aliases: [String]
    var coachingNotes: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var movementPatterns: [String]
    var actionIllustrationResourceName: String
    var muscleMapResourceName: String
}

/// App 包内的静默内容目录。目录不是用户动作库，不会自行创建 `ExerciseDefinition`。
enum BundledExerciseCatalog {
    private struct Profile {
        var coachingNotes: String
        var primaryMuscles: [String]
        var secondaryMuscles: [String]
        var movementPatterns: [String]
        var muscleMap: String
    }

    private static let squat = Profile(
        coachingNotes: "脚掌稳定踩地，膝盖跟随脚尖方向，躯干保持张力；在可控深度内完成，出现锐痛或眩晕时停止。",
        primaryMuscles: ["股四头肌", "臀大肌"],
        secondaryMuscles: ["腘绳肌", "核心", "竖脊肌", "小腿"],
        movementPatterns: ["蹲", "膝伸", "髋伸"],
        muscleMap: "soma_muscle_squat.png"
    )
    private static let kneeExtension = Profile(
        coachingNotes: "调整轴心对齐膝关节，稳定坐姿并缓慢伸膝；不要借惯性甩动，也不要强行锁死膝关节。",
        primaryMuscles: ["股四头肌"],
        secondaryMuscles: [],
        movementPatterns: ["膝伸", "器械孤立"],
        muscleMap: "soma_muscle_squat.png"
    )
    private static let kneeFlexion = Profile(
        coachingNotes: "保持髋部稳定贴靠器械，以腘绳肌控制屈膝和回程；避免腰部代偿或快速弹回。",
        primaryMuscles: ["腘绳肌"],
        secondaryMuscles: ["腓肠肌"],
        movementPatterns: ["膝屈", "器械孤立"],
        muscleMap: "soma_muscle_hip_hinge.png"
    )
    private static let hinge = Profile(
        coachingNotes: "先建立躯干张力，再向后送髋并让负重贴近身体；保持脊柱中立，以可控速度完成全程。",
        primaryMuscles: ["臀大肌", "腘绳肌", "竖脊肌"],
        secondaryMuscles: ["股四头肌", "背阔肌", "斜方肌", "核心", "前臂"],
        movementPatterns: ["髋铰链", "髋伸", "拉"],
        muscleMap: "soma_muscle_hip_hinge.png"
    )
    private static let glute = Profile(
        coachingNotes: "以髋部发力抬起，顶端保持肋骨与骨盆稳定；避免过度后仰和用腰椎代替髋伸。",
        primaryMuscles: ["臀大肌"],
        secondaryMuscles: ["腘绳肌", "核心"],
        movementPatterns: ["髋伸", "臀桥"],
        muscleMap: "soma_muscle_hip_hinge.png"
    )
    private static let lunge = Profile(
        coachingNotes: "保持前脚全脚掌受力，膝盖跟随脚尖并控制重心下降；左右侧分别记录负重与次数。",
        primaryMuscles: ["股四头肌", "臀大肌"],
        secondaryMuscles: ["腘绳肌", "内收肌", "核心", "小腿"],
        movementPatterns: ["单腿蹲", "弓步", "髋伸"],
        muscleMap: "soma_muscle_squat.png"
    )
    private static let calf = Profile(
        coachingNotes: "保持脚踝轨迹稳定，完整抬起脚跟并控制下放；不要依靠弹震完成次数。",
        primaryMuscles: ["腓肠肌", "比目鱼肌"],
        secondaryMuscles: [],
        movementPatterns: ["跖屈", "小腿孤立"],
        muscleMap: "soma_muscle_squat.png"
    )
    private static let chestPress = Profile(
        coachingNotes: "肩胛稳定贴靠支撑面，手腕与前臂保持对齐；控制下放，在肩部舒适范围内推起。",
        primaryMuscles: ["胸大肌"],
        secondaryMuscles: ["三角肌前束", "肱三头肌"],
        movementPatterns: ["水平推", "肘伸"],
        muscleMap: "soma_muscle_chest_press.png"
    )
    private static let verticalPress = Profile(
        coachingNotes: "先收紧核心和臀部，前臂保持接近垂直，再将负重稳定推过头顶；避免腰部过伸。",
        primaryMuscles: ["三角肌前束", "三角肌中束"],
        secondaryMuscles: ["肱三头肌", "胸大肌上部", "斜方肌"],
        movementPatterns: ["垂直推", "肘伸"],
        muscleMap: "soma_muscle_shoulder_press.png"
    )
    private static let shoulderIsolation = Profile(
        coachingNotes: "保持肩胛稳定，以肩部带动手臂并控制回程；选择能避免耸肩和摆动的负重。",
        primaryMuscles: ["三角肌中束"],
        secondaryMuscles: ["冈上肌", "斜方肌"],
        movementPatterns: ["肩外展", "肩部孤立"],
        muscleMap: "soma_muscle_shoulder_press.png"
    )
    private static let horizontalPull = Profile(
        coachingNotes: "先稳定躯干，再让肩胛向后下方运动并拉向身体；回程保持控制，不用腰部摆动借力。",
        primaryMuscles: ["背阔肌", "菱形肌", "斜方肌中束"],
        secondaryMuscles: ["三角肌后束", "肱二头肌", "前臂"],
        movementPatterns: ["水平拉", "肩胛后缩", "肘屈"],
        muscleMap: "soma_muscle_horizontal_pull.png"
    )
    private static let rearDelt = Profile(
        coachingNotes: "保持胸廓和肩胛稳定，以后肩和上背带动手臂；避免耸肩、摆动和过度夹背。",
        primaryMuscles: ["三角肌后束", "菱形肌"],
        secondaryMuscles: ["斜方肌中下束", "肩袖"],
        movementPatterns: ["水平外展", "肩胛后缩"],
        muscleMap: "soma_muscle_horizontal_pull.png"
    )
    private static let verticalPull = Profile(
        coachingNotes: "先让肩胛下沉，再把肘部拉向身体两侧；保持躯干稳定，避免用摆动换取行程。",
        primaryMuscles: ["背阔肌"],
        secondaryMuscles: ["肱二头肌", "菱形肌", "斜方肌", "前臂"],
        movementPatterns: ["垂直拉", "肩内收", "肘屈"],
        muscleMap: "soma_muscle_vertical_pull.png"
    )
    private static let armCurl = Profile(
        coachingNotes: "保持上臂位置稳定，以肘屈完成动作并控制下放；不要用身体摆动代替手臂发力。",
        primaryMuscles: ["肱二头肌", "肱肌"],
        secondaryMuscles: ["肱桡肌", "前臂"],
        movementPatterns: ["肘屈", "手臂孤立"],
        muscleMap: "soma_muscle_arms.png"
    )
    private static let triceps = Profile(
        coachingNotes: "保持上臂稳定，以肘伸完成动作并控制回程；避免耸肩和躯干大幅摆动。",
        primaryMuscles: ["肱三头肌"],
        secondaryMuscles: ["前臂"],
        movementPatterns: ["肘伸", "手臂孤立"],
        muscleMap: "soma_muscle_arms.png"
    )
    private static let core = Profile(
        coachingNotes: "维持自然呼吸和躯干张力，在能保持骨盆与腰椎稳定的范围内完成；不要屏息硬撑。",
        primaryMuscles: ["腹直肌", "腹横肌"],
        secondaryMuscles: ["腹斜肌", "髋屈肌", "竖脊肌"],
        movementPatterns: ["抗伸展", "躯干屈曲", "核心稳定"],
        muscleMap: "soma_muscle_core.png"
    )

    private static let entries: [BundledExerciseContent] = [
        item("杠铃深蹲", ["杠铃后蹲"], "soma_barbell_squat.png", squat),
        item("自重深蹲", ["徒手深蹲", "深蹲"], "soma_bodyweight_squat.png", squat),
        item("杠铃前蹲", ["前蹲", "颈前深蹲"], "free_Front_Squat_Clean_Grip.jpg", squat),
        item("高脚杯深蹲", ["哑铃杯式深蹲"], "free_Goblet_Squat.jpg", squat),
        item("史密斯深蹲", [], "free_Smith_Machine_Squat.jpg", squat),
        item("腿举", ["器械腿举"], "free_Leg_Press.jpg", squat),
        item("腿屈伸", ["坐姿腿屈伸"], "free_Leg_Extensions.jpg", kneeExtension),
        item("俯卧腿弯举", ["俯卧腿屈曲"], "free_Lying_Leg_Curls.jpg", kneeFlexion),
        item("罗马尼亚硬拉", ["RDL"], "free_Romanian_Deadlift.jpg", hinge),
        item("杠铃硬拉", ["传统硬拉", "硬拉"], "free_Barbell_Deadlift.jpg", hinge),
        item("相扑硬拉", [], "free_Sumo_Deadlift.jpg", hinge),
        item("杠铃臀推", ["臀推"], "free_Barbell_Hip_Thrust.jpg", glute),
        item("单腿臀桥", [], "free_Single_Leg_Glute_Bridge.jpg", glute),
        item("哑铃弓步", ["哑铃箭步蹲"], "free_Dumbbell_Lunges.jpg", lunge),
        item("保加利亚分腿蹲", ["保加利亚蹲"], "soma_split_stance_dumbbell.png", lunge),
        item("台阶上步", ["登阶"], "free_Step-up_with_Knee_Raise.jpg", lunge),
        item("站姿提踵", ["站姿小腿提踵"], "free_Standing_Calf_Raises.jpg", calf),
        item("站姿哑铃提踵", [], "free_Standing_Dumbbell_Calf_Raise.jpg", calf),
        item("杠铃卧推", ["平板杠铃卧推"], "free_Barbell_Bench_Press_-_Medium_Grip.jpg", chestPress),
        item("哑铃卧推", ["平板哑铃卧推"], "free_Dumbbell_Bench_Press.jpg", chestPress),
        item("上斜哑铃卧推", ["上斜哑铃推胸"], "free_Incline_Dumbbell_Press.jpg", chestPress),
        item("俯卧撑", [], "free_Pushups.jpg", chestPress),
        item("双杠臂屈伸", ["双杠撑体"], "free_Dips_-_Chest_Version.jpg", chestPress),
        item("蝴蝶机夹胸", ["蝴蝶机飞鸟"], "free_Butterfly.jpg", chestPress),
        item("哑铃肩推", ["哑铃推举"], "free_Dumbbell_Shoulder_Press.jpg", verticalPress),
        item("杠铃肩推", ["杠铃推举"], "free_Barbell_Shoulder_Press.jpg", verticalPress),
        item("哑铃侧平举", ["侧平举"], "free_Side_Lateral_Raise.jpg", shoulderIsolation),
        item("面拉", ["绳索面拉"], "free_Face_Pull.jpg", rearDelt),
        item("反向飞鸟", ["俯身反向飞鸟"], "free_Reverse_Flyes.jpg", rearDelt),
        item("杠铃俯身划船", ["杠铃划船"], "free_Bent_Over_Barbell_Row.jpg", horizontalPull),
        item("单臂哑铃划船", ["单手哑铃划船"], "free_One-Arm_Dumbbell_Row.jpg", horizontalPull),
        item("坐姿绳索划船", ["坐姿划船"], "free_Seated_Cable_Rows.jpg", horizontalPull),
        item("高位下拉", ["宽握高位下拉"], "soma_lat_pulldown.png", verticalPull),
        item("引体向上", ["正手引体向上"], "free_Pullups.jpg", verticalPull),
        item("反手引体向上", [], "free_Chin-Up.jpg", verticalPull),
        item("哑铃交替弯举", [], "free_Dumbbell_Alternate_Bicep_Curl.jpg", armCurl),
        item("杠铃弯举", [], "free_Barbell_Curl.jpg", armCurl),
        item("锤式弯举", [], "free_Hammer_Curls.jpg", armCurl),
        item("绳索下压", ["肱三头肌下压"], "free_Triceps_Pushdown.jpg", triceps),
        item("绳索过顶臂屈伸", [], "free_Triceps_Overhead_Extension_with_Rope.jpg", triceps),
        item("平板支撑", [], "free_Plank.jpg", core),
        item("卷腹", [], "free_Crunches.jpg", core)
    ]

    static var entryCount: Int {
        entries.count
    }

    static var resourceNames: [String] {
        Array(Set(
            entries.map(\.actionIllustrationResourceName)
                + entries.map(\.muscleMapResourceName)
                + [
                    fallbackActionIllustration.resourceName,
                    fallbackMuscleMap.resourceName
                ].compactMap { $0 }
        )).sorted()
    }

    static func content(forName name: String) -> BundledExerciseContent? {
        let key = ExerciseLibraryStore.canonicalNameKey(name)
        guard !key.isEmpty else { return nil }
        return entries.first { entry in
            ([entry.canonicalName] + entry.aliases).contains {
                ExerciseLibraryStore.canonicalNameKey($0) == key
            }
        }
    }

    @discardableResult
    static func activateIfAvailable(_ definition: ExerciseDefinition) -> Bool {
        guard let content = content(forName: definition.canonicalName) else {
            return false
        }
        var changed = false
        if definition.coachingNotes.isEmpty {
            definition.coachingNotes = content.coachingNotes
            changed = true
        }
        if definition.primaryMuscles.isEmpty {
            definition.primaryMuscles = content.primaryMuscles
            changed = true
        }
        if definition.secondaryMuscles.isEmpty {
            definition.secondaryMuscles = content.secondaryMuscles
            changed = true
        }
        if definition.movementPatterns.isEmpty {
            definition.movementPatterns = content.movementPatterns
            changed = true
        }

        var images = definition.imageReferences
        changed = reconcileBundledImage(
            kind: .actionIllustration,
            title: "内置动作示意图",
            resourceName: content.actionIllustrationResourceName,
            in: &images
        ) || changed
        changed = reconcileBundledImage(
            kind: .muscleMap,
            title: "内置通用肌群图",
            resourceName: content.muscleMapResourceName,
            in: &images
        ) || changed
        if definition.imageReferences != images {
            definition.imageReferences = images
        }
        let bundledMuscleResources = Set(entries.map(\.muscleMapResourceName))
        let currentMuscleResource = definition.muscleDiagramAssetName
        if currentMuscleResource == nil
            || (currentMuscleResource != content.muscleMapResourceName
                && currentMuscleResource.map(
                    bundledMuscleResources.contains
                ) == true)
        {
            definition.muscleDiagramAssetName = content.muscleMapResourceName
            changed = true
        }
        if changed {
            definition.updatedAt = .now
        }
        return changed
    }

    static let fallbackActionIllustration = ExerciseImageReference(
        kind: .actionIllustration,
        source: .bundled,
        title: "待补充动作示意图",
        resourceName: "soma_muscle_neutral.png",
        createdAt: .distantPast
    )

    static let fallbackMuscleMap = ExerciseImageReference(
        kind: .muscleMap,
        source: .bundled,
        title: "通用人体肌群图",
        resourceName: "soma_muscle_neutral.png",
        createdAt: .distantPast
    )

    private static func item(
        _ name: String,
        _ aliases: [String],
        _ actionIllustration: String,
        _ profile: Profile
    ) -> BundledExerciseContent {
        BundledExerciseContent(
            canonicalName: name,
            aliases: aliases,
            coachingNotes: profile.coachingNotes,
            primaryMuscles: profile.primaryMuscles,
            secondaryMuscles: profile.secondaryMuscles,
            movementPatterns: profile.movementPatterns,
            actionIllustrationResourceName: actionIllustration,
            muscleMapResourceName: profile.muscleMap
        )
    }

    private static func reconcileBundledImage(
        kind: ExerciseImageKind,
        title: String,
        resourceName: String,
        in images: inout [ExerciseImageReference]
    ) -> Bool {
        let bundled = images.filter {
            $0.kind == kind && $0.source == .bundled
        }
        if !bundled.isEmpty {
            guard bundled.count != 1
                || bundled[0].resourceName != resourceName
                || bundled[0].title != title
            else {
                return false
            }
            images.removeAll {
                $0.kind == kind && $0.source == .bundled
            }
            images.append(ExerciseImageReference(
                kind: kind,
                source: .bundled,
                title: title,
                resourceName: resourceName,
                createdAt: .distantPast
            ))
            return true
        }
        guard !images.contains(where: { $0.kind == kind }) else {
            return false
        }
        images.append(ExerciseImageReference(
            kind: kind,
            source: .bundled,
            title: title,
            resourceName: resourceName,
            createdAt: .distantPast
        ))
        return true
    }
}
