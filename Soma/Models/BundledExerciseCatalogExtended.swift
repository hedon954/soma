import Foundation

/// 纯文字扩展目录（ADR 0035 修订）：大幅扩充内置动作覆盖面。
/// 条目只提供名称、别名、教练提示、肌群与动作模式；受力图由
/// `MuscleGroupMapping` 按肌群程序生成，动作示意图留空走通用占位。
/// 名称与别名参考 free-exercise-db（CC0，800+ 动作）与常见中文动作命名。
extension BundledExerciseCatalog {
    static let extendedEntries: [BundledExerciseContent] =
        extendedLegEntries
            + extendedHingeAndGluteEntries
            + extendedPushEntries
            + extendedPullEntries
            + extendedArmEntries
            + extendedCoreEntries
            + extendedPowerAndConditioningEntries
}

// MARK: - Profiles

private struct ExtendedProfile {
    var notes: String
    var primary: [String]
    var secondary: [String]
    var patterns: [String]
    var map: String
}

private func entry(
    _ name: String,
    _ aliases: [String],
    _ profile: ExtendedProfile
) -> BundledExerciseContent {
    BundledExerciseContent(
        canonicalName: name,
        aliases: aliases,
        coachingNotes: profile.notes,
        primaryMuscles: profile.primary,
        secondaryMuscles: profile.secondary,
        movementPatterns: profile.patterns,
        actionIllustrationResourceName: "",
        muscleMapResourceName: profile.map
    )
}

private let squatProfile = ExtendedProfile(
    notes: "脚掌稳定踩地，膝盖跟随脚尖方向，躯干保持张力；在可控深度内完成，出现锐痛或眩晕时停止。",
    primary: ["股四头肌", "臀大肌"],
    secondary: ["腘绳肌", "核心", "竖脊肌", "小腿"],
    patterns: ["蹲", "膝伸", "髋伸"],
    map: "soma_muscle_squat.png"
)
private let singleLegSquatProfile = ExtendedProfile(
    notes: "单侧支撑时优先保证骨盆水平和膝盖方向，幅度由控制能力决定；左右分别记录。",
    primary: ["股四头肌", "臀大肌"],
    secondary: ["腘绳肌", "臀中肌", "核心", "小腿"],
    patterns: ["单腿蹲", "膝伸", "髋伸"],
    map: "soma_muscle_squat.png"
)
private let kneeExtensionProfile = ExtendedProfile(
    notes: "以股四头肌控制伸膝和回程，不借惯性甩动，也不强行锁死膝关节。",
    primary: ["股四头肌"],
    secondary: [],
    patterns: ["膝伸", "器械孤立"],
    map: "soma_muscle_squat.png"
)
private let kneeFlexionProfile = ExtendedProfile(
    notes: "保持髋部稳定，以腘绳肌控制屈膝和回程；避免腰部代偿或快速弹回。",
    primary: ["腘绳肌"],
    secondary: ["腓肠肌"],
    patterns: ["膝屈", "器械孤立"],
    map: "soma_muscle_hip_hinge.png"
)
private let lungeProfile = ExtendedProfile(
    notes: "前脚全脚掌受力，膝盖跟随脚尖并控制重心下降；左右侧分别记录负重与次数。",
    primary: ["股四头肌", "臀大肌"],
    secondary: ["腘绳肌", "内收肌", "核心", "小腿"],
    patterns: ["单腿蹲", "弓步", "髋伸"],
    map: "soma_muscle_squat.png"
)
private let calfProfile = ExtendedProfile(
    notes: "脚踝轨迹稳定，完整抬起脚跟并控制下放；不要依靠弹震完成次数。",
    primary: ["腓肠肌", "比目鱼肌"],
    secondary: [],
    patterns: ["跖屈", "小腿孤立"],
    map: "soma_muscle_squat.png"
)
private let hingeProfile = ExtendedProfile(
    notes: "先建立躯干张力，再向后送髋并让负重贴近身体；保持脊柱中立，以可控速度完成全程。",
    primary: ["臀大肌", "腘绳肌", "竖脊肌"],
    secondary: ["股四头肌", "背阔肌", "斜方肌", "核心", "前臂"],
    patterns: ["髋铰链", "髋伸", "拉"],
    map: "soma_muscle_hip_hinge.png"
)
private let singleLegHingeProfile = ExtendedProfile(
    notes: "单腿支撑下向后送髋，骨盆保持水平，负重贴近腿部下放；以平衡可控为前提加重。",
    primary: ["腘绳肌", "臀大肌"],
    secondary: ["竖脊肌", "臀中肌", "核心"],
    patterns: ["髋铰链", "单腿", "髋伸"],
    map: "soma_muscle_hip_hinge.png"
)
private let gluteProfile = ExtendedProfile(
    notes: "以髋部发力抬起，顶端保持肋骨与骨盆稳定；避免过度后仰和用腰椎代替髋伸。",
    primary: ["臀大肌"],
    secondary: ["腘绳肌", "核心"],
    patterns: ["髋伸", "臀桥"],
    map: "soma_muscle_hip_hinge.png"
)
private let hipAbductionProfile = ExtendedProfile(
    notes: "骨盆保持稳定，以髋外侧发力打开；控制回程速度，不靠躯干侧倾借力。",
    primary: ["臀中肌"],
    secondary: ["臀大肌"],
    patterns: ["髋外展"],
    map: "soma_muscle_hip_hinge.png"
)
private let hipAdductionProfile = ExtendedProfile(
    notes: "在无夹痛的活动范围内以大腿内侧发力合拢，控制回程；不要用惯性快速开合。",
    primary: ["内收肌"],
    secondary: [],
    patterns: ["髋内收"],
    map: "soma_muscle_squat.png"
)
private let backExtensionProfile = ExtendedProfile(
    notes: "以髋为轴心带动躯干，顶端不过度后伸腰椎；下背不适时缩小幅度。",
    primary: ["竖脊肌", "臀大肌"],
    secondary: ["腘绳肌"],
    patterns: ["髋伸", "躯干伸展"],
    map: "soma_muscle_hip_hinge.png"
)
private let chestPressProfile = ExtendedProfile(
    notes: "肩胛稳定贴靠支撑面，手腕与前臂保持对齐；控制下放，在肩部舒适范围内推起。",
    primary: ["胸大肌"],
    secondary: ["三角肌前束", "肱三头肌"],
    patterns: ["水平推", "肘伸"],
    map: "soma_muscle_chest_press.png"
)
private let chestFlyProfile = ExtendedProfile(
    notes: "保持肘部微屈的固定角度，以胸部收缩带动手臂合拢；离心阶段控制在肩部舒适范围。",
    primary: ["胸大肌"],
    secondary: ["三角肌前束"],
    patterns: ["水平内收", "胸部孤立"],
    map: "soma_muscle_chest_press.png"
)
private let closeGripPressProfile = ExtendedProfile(
    notes: "窄距握距下保持手腕中立、肘部贴近身体；以三头与胸部协同完成推起。",
    primary: ["肱三头肌", "胸大肌"],
    secondary: ["三角肌前束"],
    patterns: ["水平推", "肘伸"],
    map: "soma_muscle_arms.png"
)
private let verticalPressProfile = ExtendedProfile(
    notes: "先收紧核心和臀部，前臂保持接近垂直，再将负重稳定推过头顶；避免腰部过伸。",
    primary: ["三角肌前束", "三角肌中束"],
    secondary: ["肱三头肌", "斜方肌"],
    patterns: ["垂直推", "肘伸"],
    map: "soma_muscle_shoulder_press.png"
)
private let lateralRaiseProfile = ExtendedProfile(
    notes: "保持肩胛稳定，以肩部带动手臂并控制回程；选择能避免耸肩和摆动的负重。",
    primary: ["三角肌中束"],
    secondary: ["斜方肌"],
    patterns: ["肩外展", "肩部孤立"],
    map: "soma_muscle_shoulder_press.png"
)
private let frontRaiseProfile = ExtendedProfile(
    notes: "躯干保持稳定，以前肩带动手臂抬至约与肩同高；控制下放，不借身体摆动。",
    primary: ["三角肌前束"],
    secondary: ["三角肌中束"],
    patterns: ["肩前屈", "肩部孤立"],
    map: "soma_muscle_shoulder_press.png"
)
private let rearDeltProfile = ExtendedProfile(
    notes: "保持胸廓和肩胛稳定，以后肩和上背带动手臂；避免耸肩、摆动和过度夹背。",
    primary: ["三角肌后束"],
    secondary: ["上背", "斜方肌"],
    patterns: ["水平外展", "肩胛后缩"],
    map: "soma_muscle_horizontal_pull.png"
)
private let uprightRowProfile = ExtendedProfile(
    notes: "沿身体近距离上提，肘部引导且不高于肩部太多；肩部有夹挤感时改用其他动作。",
    primary: ["三角肌中束", "斜方肌"],
    secondary: ["肱二头肌", "前臂"],
    patterns: ["垂直拉", "肩外展"],
    map: "soma_muscle_shoulder_press.png"
)
private let shrugProfile = ExtendedProfile(
    notes: "垂直向上耸肩并稍作停顿，控制下放；不要转动肩关节或用弹震借力。",
    primary: ["斜方肌"],
    secondary: ["前臂", "颈部"],
    patterns: ["肩胛上提"],
    map: "soma_muscle_horizontal_pull.png"
)
private let horizontalPullProfile = ExtendedProfile(
    notes: "先稳定躯干，再让肩胛向后下方运动并拉向身体；回程保持控制，不用腰部摆动借力。",
    primary: ["背阔肌", "上背"],
    secondary: ["三角肌后束", "肱二头肌", "前臂"],
    patterns: ["水平拉", "肩胛后缩", "肘屈"],
    map: "soma_muscle_horizontal_pull.png"
)
private let verticalPullProfile = ExtendedProfile(
    notes: "先让肩胛下沉，再把肘部拉向身体两侧；保持躯干稳定，避免用摆动换取行程。",
    primary: ["背阔肌"],
    secondary: ["肱二头肌", "上背", "前臂"],
    patterns: ["垂直拉", "肩内收", "肘屈"],
    map: "soma_muscle_vertical_pull.png"
)
private let pulloverProfile = ExtendedProfile(
    notes: "保持肘部角度固定，以背阔肌带动手臂划弧；肩部活动度不足时缩小幅度。",
    primary: ["背阔肌"],
    secondary: ["胸大肌", "肱三头肌"],
    patterns: ["肩伸展", "背部孤立"],
    map: "soma_muscle_vertical_pull.png"
)
private let armCurlProfile = ExtendedProfile(
    notes: "保持上臂位置稳定，以肘屈完成动作并控制下放；不要用身体摆动代替手臂发力。",
    primary: ["肱二头肌"],
    secondary: ["前臂"],
    patterns: ["肘屈", "手臂孤立"],
    map: "soma_muscle_arms.png"
)
private let reverseCurlProfile = ExtendedProfile(
    notes: "正握或锤握下保持手腕中立，以前臂和肱肌控制弯举全程；负重宜小、控制优先。",
    primary: ["前臂", "肱二头肌"],
    secondary: [],
    patterns: ["肘屈", "前臂"],
    map: "soma_muscle_arms.png"
)
private let tricepsProfile = ExtendedProfile(
    notes: "保持上臂稳定，以肘伸完成动作并控制回程；避免耸肩和躯干大幅摆动。",
    primary: ["肱三头肌"],
    secondary: ["前臂"],
    patterns: ["肘伸", "手臂孤立"],
    map: "soma_muscle_arms.png"
)
private let forearmProfile = ExtendedProfile(
    notes: "前臂支撑稳定，只以手腕完成屈伸；使用小负重高控制，避免腕关节疼痛。",
    primary: ["前臂"],
    secondary: [],
    patterns: ["腕屈伸", "前臂孤立"],
    map: "soma_muscle_arms.png"
)
private let coreFlexProfile = ExtendedProfile(
    notes: "以腹部收缩带动躯干卷起，下背保持贴地或稳定；不要用手拉头颈借力。",
    primary: ["腹直肌"],
    secondary: ["腹斜肌"],
    patterns: ["躯干屈曲", "核心"],
    map: "soma_muscle_core.png"
)
private let coreStabilityProfile = ExtendedProfile(
    notes: "维持自然呼吸和躯干张力，在能保持骨盆与腰椎稳定的范围内完成；不要屏息硬撑。",
    primary: ["腹直肌", "核心"],
    secondary: ["腹斜肌", "竖脊肌"],
    patterns: ["抗伸展", "核心稳定"],
    map: "soma_muscle_core.png"
)
private let obliqueProfile = ExtendedProfile(
    notes: "以腹斜肌控制旋转或侧屈，骨盆保持稳定；速度放慢，不追求大幅甩动。",
    primary: ["腹斜肌"],
    secondary: ["腹直肌", "核心"],
    patterns: ["旋转", "抗旋转", "核心"],
    map: "soma_muscle_core.png"
)
private let legRaiseProfile = ExtendedProfile(
    notes: "以下腹发力带动骨盆后倾抬腿，控制下放不塌腰；摆动幅度以躯干稳定为限。",
    primary: ["腹直肌"],
    secondary: ["腹斜肌", "股四头肌"],
    patterns: ["髋屈", "躯干屈曲", "核心"],
    map: "soma_muscle_core.png"
)
private let powerProfile = ExtendedProfile(
    notes: "以髋部爆发带动负重，动作全程保持脊柱中立；技术优先于重量，疲劳时及时停止。",
    primary: ["臀大肌", "腘绳肌"],
    secondary: ["股四头肌", "斜方肌", "竖脊肌", "三角肌", "前臂"],
    patterns: ["爆发", "髋伸", "三关节伸展"],
    map: "soma_muscle_hip_hinge.png"
)
private let carryProfile = ExtendedProfile(
    notes: "握紧负重、躯干直立行走，肩胛微收不耸肩；步幅稳定，握力衰竭前放下。",
    primary: ["前臂", "斜方肌"],
    secondary: ["核心", "臀大肌"],
    patterns: ["负重行走", "握力", "核心稳定"],
    map: "soma_muscle_core.png"
)
private let conditioningProfile = ExtendedProfile(
    notes: "以稳定节奏完成全身动作，落地和支撑保持关节缓冲；心率过高时主动降速。",
    primary: ["股四头肌", "臀大肌"],
    secondary: ["核心", "胸大肌", "三角肌前束", "小腿"],
    patterns: ["全身", "体能"],
    map: "soma_muscle_neutral.png"
)
private let neckProfile = ExtendedProfile(
    notes: "小幅度、慢速度完成颈部屈伸，全程无疼痛与眩晕；负重训练需有经验基础。",
    primary: ["颈部"],
    secondary: ["斜方肌"],
    patterns: ["颈屈伸"],
    map: "soma_muscle_neutral.png"
)

// MARK: - Entries

private let extendedLegEntries: [BundledExerciseContent] = [
    entry("哈克深蹲", ["哈克机深蹲", "Hack Squat"], squatProfile),
    entry("哑铃深蹲", [], squatProfile),
    entry("壶铃深蹲", [], squatProfile),
    entry("宽距深蹲", ["相扑深蹲"], squatProfile),
    entry("箱式深蹲", ["坐箱深蹲"], squatProfile),
    entry("暂停深蹲", ["停顿深蹲"], squatProfile),
    entry("泽奇深蹲", ["Zercher 深蹲"], squatProfile),
    entry("过头深蹲", ["杠铃过头深蹲"], squatProfile),
    entry("杰佛逊深蹲", [], squatProfile),
    entry("靠墙静蹲", ["靠墙蹲", "静蹲"], kneeExtensionProfile),
    entry("深蹲跳", ["跳跃深蹲"], squatProfile),
    entry("手枪蹲", ["单腿深蹲"], singleLegSquatProfile),
    entry("滑冰者深蹲", ["滑冰式深蹲"], singleLegSquatProfile),
    entry("西斯深蹲", ["Sissy Squat"], kneeExtensionProfile),
    entry("单腿腿屈伸", [], kneeExtensionProfile),
    entry("坐姿腿弯举", [], kneeFlexionProfile),
    entry("站姿腿弯举", ["单腿站姿腿弯举"], kneeFlexionProfile),
    entry("北欧腿弯举", ["跪姿腿弯举", "Nordic Curl"], kneeFlexionProfile),
    entry("瑞士球腿弯举", ["健身球腿弯举"], kneeFlexionProfile),
    entry("滑盘腿弯举", ["滑垫腿弯举"], kneeFlexionProfile),
    entry("杠铃弓步", ["杠铃箭步蹲"], lungeProfile),
    entry("行走弓步", ["箭步蹲行走", "行走箭步蹲"], lungeProfile),
    entry("后撤弓步", ["反向弓步", "后撤箭步蹲"], lungeProfile),
    entry("侧弓步", ["哥萨克深蹲"], lungeProfile),
    entry("原地分腿蹲", ["分腿蹲", "静态弓步"], lungeProfile),
    entry("坐姿提踵", ["坐姿小腿提踵"], calfProfile),
    entry("腿举机提踵", ["倒蹬机提踵"], calfProfile),
    entry("单腿提踵", ["单脚提踵"], calfProfile),
    entry("骑驴提踵", [], calfProfile),
    entry("器械髋外展", ["坐姿髋外展", "髋外展机"], hipAbductionProfile),
    entry("弹力带侧走", ["螃蟹走", "怪兽走"], hipAbductionProfile),
    entry("侧卧抬腿", ["侧卧髋外展"], hipAbductionProfile),
    entry("蚌式开合", ["侧卧蚌式"], hipAbductionProfile),
    entry("器械髋内收", ["坐姿髋内收", "夹腿机"], hipAdductionProfile)
]

private let extendedHingeAndGluteEntries: [BundledExerciseContent] = [
    entry("直腿硬拉", ["杠铃直腿硬拉"], hingeProfile),
    entry("哑铃罗马尼亚硬拉", ["哑铃RDL", "哑铃直腿硬拉"], hingeProfile),
    entry("六角杠硬拉", ["菱形杠硬拉", "Trap Bar 硬拉"], hingeProfile),
    entry("架上硬拉", ["架上拉", "半程硬拉", "Rack Pull"], hingeProfile),
    entry("赤字硬拉", ["垫高硬拉"], hingeProfile),
    entry("壶铃硬拉", [], hingeProfile),
    entry("早安式", ["早安动作", "杠铃体前屈"], hingeProfile),
    entry("单腿硬拉", ["单腿罗马尼亚硬拉", "单腿RDL"], singleLegHingeProfile),
    entry("臀桥", ["徒手臀桥", "仰卧臀桥"], gluteProfile),
    entry("负重臀桥", ["杠铃臀桥"], gluteProfile),
    entry("单腿臀推", [], gluteProfile),
    entry("器械臀推", ["臀推机"], gluteProfile),
    entry("绳索髋伸", ["绳索后踢腿", "驴踢腿"], gluteProfile),
    entry("跪姿后踢腿", ["四足后踢腿", "跪姿抬腿"], gluteProfile),
    entry("山羊挺身", ["罗马椅挺身", "背部伸展"], backExtensionProfile),
    entry("反向山羊挺身", ["反向挺身"], backExtensionProfile),
    entry("超人式", ["俯卧两头起"], backExtensionProfile)
]

private let extendedPushEntries: [BundledExerciseContent] = [
    entry("上斜杠铃卧推", ["上斜卧推"], chestPressProfile),
    entry("下斜杠铃卧推", ["下斜卧推"], chestPressProfile),
    entry("下斜哑铃卧推", [], chestPressProfile),
    entry("器械推胸", ["坐姿推胸", "悍马机推胸"], chestPressProfile),
    entry("史密斯卧推", [], chestPressProfile),
    entry("地板卧推", ["Floor Press"], chestPressProfile),
    entry("跪姿俯卧撑", [], chestPressProfile),
    entry("上斜俯卧撑", ["推墙俯卧撑"], chestPressProfile),
    entry("下斜俯卧撑", ["脚垫高俯卧撑"], chestPressProfile),
    entry("负重俯卧撑", [], chestPressProfile),
    entry("哑铃飞鸟", ["平板哑铃飞鸟"], chestFlyProfile),
    entry("上斜哑铃飞鸟", [], chestFlyProfile),
    entry("绳索夹胸", ["龙门架夹胸", "十字夹胸"], chestFlyProfile),
    entry("低位绳索夹胸", ["绳索上斜飞鸟", "上提夹胸"], chestFlyProfile),
    entry("高位绳索夹胸", ["绳索下拉夹胸"], chestFlyProfile),
    entry("窄距卧推", ["窄握卧推"], closeGripPressProfile),
    entry("窄距俯卧撑", ["钻石俯卧撑"], closeGripPressProfile),
    entry("站姿杠铃推举", ["军事推举", "实力推举"], verticalPressProfile),
    entry("阿诺德推举", [], verticalPressProfile),
    entry("坐姿哑铃推举", ["坐姿哑铃肩推"], verticalPressProfile),
    entry("器械肩推", ["坐姿器械肩推"], verticalPressProfile),
    entry("单臂哑铃推举", [], verticalPressProfile),
    entry("借力推举", ["Push Press"], verticalPressProfile),
    entry("颈后推举", ["杠铃颈后推举"], verticalPressProfile),
    entry("地雷管推举", ["地雷架推举", "landmine 推举"], verticalPressProfile),
    entry("倒立撑", ["靠墙倒立撑"], verticalPressProfile),
    entry("坐姿侧平举", [], lateralRaiseProfile),
    entry("绳索侧平举", ["单臂绳索侧平举"], lateralRaiseProfile),
    entry("器械侧平举", [], lateralRaiseProfile),
    entry("前平举", ["哑铃前平举"], frontRaiseProfile),
    entry("杠铃片前平举", [], frontRaiseProfile),
    entry("蝴蝶机反向飞鸟", ["反向蝶机"], rearDeltProfile),
    entry("绳索反向飞鸟", [], rearDeltProfile),
    entry("直立划船", ["杠铃直立划船"], uprightRowProfile),
    entry("哑铃直立划船", [], uprightRowProfile),
    entry("杠铃耸肩", [], shrugProfile),
    entry("哑铃耸肩", [], shrugProfile),
    entry("史密斯耸肩", ["史密斯器械耸肩"], shrugProfile)
]

private let extendedPullEntries: [BundledExerciseContent] = [
    entry("T杠划船", ["T杆划船", "T-Bar Row"], horizontalPullProfile),
    entry("平板哑铃划船", ["胸部支撑哑铃划船", "上斜哑铃划船"], horizontalPullProfile),
    entry("水平引体", ["反向划船", "澳大利亚引体", "低杠引体"], horizontalPullProfile),
    entry("器械划船", ["坐姿器械划船"], horizontalPullProfile),
    entry("彭德利划船", ["Pendlay Row"], horizontalPullProfile),
    entry("单臂绳索划船", [], horizontalPullProfile),
    entry("海豹划船", ["Seal Row"], horizontalPullProfile),
    entry("反握杠铃划船", ["反手杠铃划船"], horizontalPullProfile),
    entry("地雷管划船", ["landmine 划船"], horizontalPullProfile),
    entry("反握高位下拉", [], verticalPullProfile),
    entry("窄距高位下拉", ["中立握高位下拉", "V柄高位下拉"], verticalPullProfile),
    entry("单臂高位下拉", [], verticalPullProfile),
    entry("辅助引体向上", ["助力引体向上"], verticalPullProfile),
    entry("中立握引体向上", ["对握引体向上"], verticalPullProfile),
    entry("宽握引体向上", ["宽距引体向上"], verticalPullProfile),
    entry("哑铃仰卧上拉", ["哑铃 Pullover", "仰卧过顶上拉"], pulloverProfile),
    entry("直臂下拉", ["绳索直臂下压", "直臂下压"], pulloverProfile)
]

private let extendedArmEntries: [BundledExerciseContent] = [
    entry("集中弯举", ["集中式弯举"], armCurlProfile),
    entry("牧师椅弯举", ["斜托弯举", "牧师凳弯举"], armCurlProfile),
    entry("上斜哑铃弯举", ["上斜凳弯举"], armCurlProfile),
    entry("绳索弯举", ["拉索弯举"], armCurlProfile),
    entry("EZ杠弯举", ["曲杠弯举", "曲柄杠铃弯举"], armCurlProfile),
    entry("坐姿哑铃弯举", [], armCurlProfile),
    entry("器械弯举", ["MTS 二头弯举"], armCurlProfile),
    entry("高位绳索弯举", ["绳索头上弯举"], armCurlProfile),
    entry("反握弯举", ["反向弯举", "正握弯举"], reverseCurlProfile),
    entry("佐特曼弯举", ["Zottman 弯举"], reverseCurlProfile),
    entry("仰卧臂屈伸", ["仰卧杠铃臂屈伸", "碎颅者"], tricepsProfile),
    entry("哑铃颈后臂屈伸", ["坐姿颈后臂屈伸", "过头哑铃臂屈伸"], tricepsProfile),
    entry("凳上臂屈伸", ["凳式臂屈伸", "板凳臂屈伸"], tricepsProfile),
    entry("俯身哑铃臂屈伸", ["哑铃后踢", "三头后踢"], tricepsProfile),
    entry("单臂绳索下压", ["反握绳索下压"], tricepsProfile),
    entry("器械臂屈伸", ["三头肌伸展机"], tricepsProfile),
    entry("腕弯举", ["正握腕弯举", "手腕弯举"], forearmProfile),
    entry("反握腕弯举", ["腕伸展", "反向手腕弯举"], forearmProfile),
    entry("手腕滚轮", ["腕力滚轮"], forearmProfile),
    entry("单杠悬挂", ["悬挂握力", "死吊"], carryProfile)
]

private let extendedCoreEntries: [BundledExerciseContent] = [
    entry("仰卧起坐", [], coreFlexProfile),
    entry("绳索卷腹", ["跪姿绳索卷腹"], coreFlexProfile),
    entry("器械卷腹", [], coreFlexProfile),
    entry("反向卷腹", [], coreFlexProfile),
    entry("V字两头起", ["两头起", "V-Up"], coreFlexProfile),
    entry("自行车卷腹", ["交替卷腹", "空中蹬车"], obliqueProfile),
    entry("俄罗斯转体", [], obliqueProfile),
    entry("侧平板支撑", ["侧桥", "侧平板"], obliqueProfile),
    entry("帕洛夫推", ["Pallof Press", "抗旋转推"], obliqueProfile),
    entry("绳索砍伐", ["伐木动作", "木刀砍"], obliqueProfile),
    entry("悬垂举腿", ["悬垂抬腿", "悬垂直腿上摆"], legRaiseProfile),
    entry("悬垂屈膝抬腿", ["悬垂提膝"], legRaiseProfile),
    entry("仰卧举腿", ["仰卧抬腿"], legRaiseProfile),
    entry("龙旗", ["Dragon Flag"], legRaiseProfile),
    entry("健腹轮", ["腹轮", "AB Wheel"], coreStabilityProfile),
    entry("死虫式", ["Dead Bug"], coreStabilityProfile),
    entry("鸟狗式", ["Bird Dog"], coreStabilityProfile),
    entry("登山跑", ["登山者", "Mountain Climber"], coreStabilityProfile),
    entry("颈部屈伸", ["颈屈伸", "颈桥"], neckProfile)
]

private let extendedPowerAndConditioningEntries: [BundledExerciseContent] = [
    entry("壶铃摆动", ["壶铃摇摆", "Kettlebell Swing"], powerProfile),
    entry("高翻", ["杠铃高翻", "Power Clean"], powerProfile),
    entry("抓举", ["杠铃抓举"], powerProfile),
    entry("挺举", ["杠铃挺举"], powerProfile),
    entry("哑铃抓举", ["单臂哑铃抓举"], powerProfile),
    entry("杠铃高拉", ["高拉"], powerProfile),
    entry("土耳其起立", ["壶铃土耳其起立"], coreStabilityProfile),
    entry("农夫行走", ["农夫走路", "重物行走"], carryProfile),
    entry("单侧负重行走", ["手提箱行走"], carryProfile),
    entry("波比跳", ["Burpee"], conditioningProfile),
    entry("开合跳", ["Jumping Jack"], conditioningProfile),
    entry("跳箱", ["箱式跳跃", "Box Jump"], conditioningProfile),
    entry("战绳", ["战斗绳", "Battle Rope"], conditioningProfile),
    entry("推雪橇", ["雪橇推", "雪橇冲刺"], conditioningProfile),
    entry("拉雪橇", ["雪橇拉"], conditioningProfile),
    entry("熊爬", ["Bear Crawl"], conditioningProfile),
    entry("药球砸地", ["药球砸击", "Med Ball Slam"], powerProfile)
]
