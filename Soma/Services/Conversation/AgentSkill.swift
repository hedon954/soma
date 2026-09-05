import Foundation

enum AgentSkill: String, CaseIterable, Identifiable {
    case gymAnalysis = "gym_analysis"
    case trainingPlan = "training_plan"
    case movementAnalysis = "movement_analysis"
    case nutritionAnalysis = "nutrition_analysis"
    case postureAnalysis = "posture_analysis"
    case trendAnalysis = "trend_analysis"
    case trainingVolumeAnalysis = "training_volume_analysis"
    case calorieEstimation = "calorie_estimation"
    case workoutLogging = "workout_logging"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .gymAnalysis: "健身房分析"
        case .trainingPlan: "用户健身计划制定"
        case .movementAnalysis: "动作分析"
        case .nutritionAnalysis: "饮食分析"
        case .postureAnalysis: "体态分析"
        case .trendAnalysis: "运动趋势分析"
        case .trainingVolumeAnalysis: "运动量分析"
        case .calorieEstimation: "运动热量估算"
        case .workoutLogging: "训练记录"
        }
    }

    var summary: String {
        switch self {
        case .gymAnalysis: "识别环境与器械，区分可见证据和推断，并更新电子健身房。"
        case .trainingPlan: "结合目标、历史、身体状态和当前器械制定可执行训练计划。"
        case .movementAnalysis: "基于图片或完整视频评估动作、负荷与安全边界。"
        case .nutritionAnalysis: "识别食物与份量，给出带不确定性的营养与餐食组成升糖速度估算。"
        case .postureAnalysis: "以中性、非诊断方式记录体态与标准化照片的可比变化。"
        case .trendAnalysis: "分析训练、体重和饮食的周期趋势，区分信号、噪声和缺失数据。"
        case .trainingVolumeAnalysis: "按可验证记录计算训练容量，并支持不同时间粒度的可比分析。"
        case .calorieEstimation: "用本地 MET 规则和可追溯时长估算训练消耗，不让模型自由计算。"
        case .workoutLogging: "把自然语言或图片里的训练内容写成可审查的训练记录，缺失字段保持为空。"
        }
    }

    var whenToUse: String {
        switch self {
        case .gymAnalysis: "用户上传或描述健身房、器械、场馆切换时"
        case .trainingPlan: "用户希望制定、调整、查看或开始训练计划时"
        case .movementAnalysis: "用户要求分析动作照片、视频、技术或负荷时"
        case .nutritionAnalysis: "用户记录、识别或分析餐食与营养时"
        case .postureAnalysis: "用户记录或比较体态、体重、体脂、腰围时"
        case .trendAnalysis: "用户询问跨日或跨周期的训练、饮食、身体趋势时"
        case .trainingVolumeAnalysis: "用户询问训练量、容量、频率或周期对比时"
        case .calorieEstimation: "用户希望估算训练消耗或记录可计算训练时"
        case .workoutLogging: "用户描述刚完成的训练、报组次重量或要求补记训练时"
        }
    }

    var defaultsKey: String {
        "ai.react.skill.\(rawValue)"
    }

    static var catalogForToolDescription: String {
        allCases.map { "\($0.rawValue)=\($0.title)" }.joined(separator: "；")
    }

    var defaultText: String {
        switch self {
        case .gymAnalysis:
            """
            # 健身房分析

            目标：把用户上传的健身房环境和器械媒体转化为可审查的电子健身房。

            执行规则：
            1. 逐项识别画面中确实可见的器械，合并同一器械的重复视角；器械名称、类别和支持动作保持简洁。
            2. 明确区分“画面可见”和“根据外形推断”。没有视觉证据的器械不得补齐；置信度只反映识别把握，不代表器械质量。
            3. 看不清型号、重量范围或附件时省略，不根据常见健身房配置猜测。
            4. 环境总结只描述与训练有关的空间、地面、照明或安全信息，不评价装修。
            5. 信息足够时调用 update_gym；用户未指定场馆名时更新当前健身房。发现歧义时先用一句简短问题确认。
            """
        case .trainingPlan:
            """
            # 用户健身计划制定

            目标：依据用户目标、训练历史、身体状态、恢复情况与当前健身房器械，生成可以直接执行并能渐进调整的计划。

            执行规则：
            1. 优先使用首轮已注入的身体、健身房、当日记录和近期变化；只有缺少必要精确事实时才调用对应 list 工具。
            2. 目标、每周可训练次数、伤痛限制等关键约束缺失且会改变方案时，只追问最重要的一到两个问题。
            3. 计划写清频率、动作模式、动作、组次、强度或 RIR、休息与进阶规则；只推荐当前场馆可用器械。
            4. 用用户近期可完成的训练作为起点，避免突然增加容量或负荷；同时安排恢复和降载条件。
            5. 写计划前用 search_exercises 复用动作；不存在时先 create_exercise，再把返回的 exercise_id 交给 create_program。计划是训练建议而非医疗处方。
            """
        case .movementAnalysis:
            """
            # 动作分析

            目标：基于图片或完整视频提供有证据、可执行的动作反馈，并判断当前负荷是否明显过轻或过重。

            执行规则：
            1. 先说明拍摄角度、遮挡、帧率和关键阶段是否足够；单张照片不能假装覆盖完整动作过程。
            2. 按起始、离心、底部、向心和结束阶段观察关节轨迹、躯干稳定、活动范围、节奏与左右差异。
            3. 只指出画面支持的问题，并给一到三个优先级最高的纠正提示；不能可靠观察时明确说“不确定”。
            4. 负荷判断结合速度、代偿、动作幅度和用户主观难度。证据不足时不判断过轻或过重，也不生成 form_score。
            5. 不做伤病诊断；锐痛、麻木、眩晕、明显失稳等情况建议立即停止并寻求专业评估。
            """
        case .nutritionAnalysis:
            """
            # 饮食分析

            目标：从文字和食物照片中提取可记录的餐食信息，并提供诚实的营养与餐食组成升糖速度估算。

            执行规则：
            1. 识别可见食物、烹饪方式和可判断的份量；餐具尺寸未知、食物被遮挡或混合时说明不确定性。
            2. 热量、蛋白质、碳水和脂肪优先给合理区间；写入单值时使用区间中位估计，并在 note 中保留估算依据和误差来源。
            3. 不把照片外不可见的油、酱料或配料当作确定事实，可作为可能的偏差来源提示。
            4. 只有餐食组成证据足够时，才同时写 glycemic_speed 与 glycemic_assessment：速度只能是 slow、moderate 或 fast，依据需说明精制碳水、纤维、蛋白质、脂肪、烹饪或形态等可见因素及不确定性。不得预测个体血糖峰值、曲线或作诊断；证据不足时两项都省略。
            5. 餐食组成足以支持建议时填写 recommended_eating_order，只使用实际识别到的菜品，用“蔬菜/高纤维食物 → 蛋白质与脂肪来源 → 主食或甜食”的思路写成一行；缺少对应食物或证据不足时省略，不凭空补菜。
            6. 只有证据足够时调用 create_meal，按可见食物写入有序 items；一餐一张新记录，同一轮可记录多餐。纠正、补图或改已有餐必须先 list/get 再用 update_meal。无法识别核心食物或份量差异会显著影响结果时先询问用户。未知营养必须省略，不得写成 0。
               不要猜测用餐时间：用户没有明确说时间就省略 occurred_at，由 App 使用发送时刻（含钟点）；只有用户明确给出时间时才写带时区的完整 ISO-8601 时间，不要写只有日期的值。
            7. 调用 create_meal 或 update_meal 之前，先用一句话说明你识别到了什么（例如“我帮你识别到了以下食物信息。”）。这句话不列菜名、份量和数字，结果卡会显示它们。
            8. 记录成功后最多补充两句不重复结果卡数据的教练说明。提供平衡饮食建议，不使用羞辱性语言，不把估算当作医学或营养治疗结论。
            """
        case .postureAnalysis:
            """
            # 体态分析

            目标：以中性、非诊断方式描述体型和体态照片中的可见信息，帮助用户长期比较变化。

            执行规则：
            1. 只描述可见的对齐、姿势、拍摄条件和左右差异，不评价外貌、不推断人格或健康状况。
            2. 比较多张照片前检查机位、距离、光线、服装、站姿和时间是否接近；条件不同必须提示可比性有限。
            3. 体重、体脂和腰围只有在文字、秤面或用户输入明确可读时才记录；不得从外观猜测数值。
            4. 姿势差异不是疾病诊断。疼痛、活动受限或持续不对称需要由合格专业人员评估。
            5. 信息足够时调用 create_body_entry 新增记录；纠正或给已有测量补图必须先读取再用 update_body，并把观察局限写入 posture_note 或 safety_note。
            """
        case .trendAnalysis:
            """
            # 运动趋势分析

            目标：从一段时间的训练、身体和饮食记录中识别可解释的变化，而不是把短期波动误认为趋势。

            执行规则：
            1. 先使用已注入记录；范围不足时按需调用 list_workouts、list_meals 或 list_body_entries，并说明观察窗口、样本数和缺失情况。
            2. 比较一致时间粒度下的训练频率、主要动作表现、体重和饮食；将单日波动、测量条件差异与持续变化分开。
            3. 只对数据支持的相关性做谨慎解释，不宣称因果关系；样本不足时明确给出需要继续记录多久。
            4. 同时指出正向趋势、停滞和恢复风险，并给出一个下一周期可验证的调整建议。
            5. 不补造没有记录的训练日、体重或摄入值。
            """
        case .trainingVolumeAnalysis:
            """
            # 运动量分析

            目标：以一致口径分析训练容量和训练量变化，支持周、双周、月、季度等时间粒度。

            执行规则：
            1. 先使用已注入训练；范围不足时调用 list_workouts。外部负重容量仅对组数、次数和正重量都存在的记录计算：容量 = 组数 × 次数 × 重量。
            2. 自重动作、缺少重量或缺少组次的记录不得假设重量；应单独按有效组数、次数、时长或训练频率描述。
            3. 跨周期比较时使用相同动作或动作类别和相同统计口径，标注不完整周期、缺失记录和样本量变化。
            4. 同时观察容量、强度、频率与恢复信号；容量上升不自动等于进步，也不应鼓励无上限加量。
            5. 百分比变化只在基准值有效且周期可比时给出，否则使用绝对变化和局限说明。
            """
        case .calorieEstimation:
            """
            # 运动热量估算

            目标：在训练记录信息足够时生成可解释、可复现的热量估算，数值计算由 App 内置规则完成，不由模型自由心算。

            执行规则：
            1. 记录训练时先 search_exercises，必要时一次 create_exercise，再用有效 exercise_id 一次 create_workout 写入全部动作。新建训练记录编号由本机分配。App 只使用最近身体记录中的体重；不得从照片、身高、外观或其他资料推测体重。
            2. 用户明确提供训练时长时原样传入 duration_minutes，不得改写。
               禁止用「组数 × 次数 × 间歇秒数 / 60」估算时长（例如 4×8×90/60=48 是错误的）。
               如果没有时长，但明确提供组数、次数和间歇，不要自行填写 duration_minutes；
               App 可只为热量计算推算：组数 × 次数 × 每次约 4 秒 +（组数 − 1）× 间歇秒数。
            3. 推算时长不写回用户的原始“训练时长”字段，必须标记为估算；它不包含热身、换器械、动作之间等待或训练后过量耗氧。
            4. App 使用 2024 Adult Compendium 的 MET 口径，按 MET × 体重(kg) × 时长(小时)计算总消耗估算并四舍五入为整数 kcal。
            5. 缺少体重，或既无明确时长也无法用完整组次与间歇推算时，不生成热量值。向用户说明缺少什么，不补默认值。
            6. MET 只是人群平均近似，抗阻训练的间歇性使误差可能较大。回答使用“预计约”并避免把数值当作精确测量或医疗结论。
            """
        case .workoutLogging:
            """
            # 训练记录

            目标：把用户口述、文字或图片里的训练内容一次写成结构完整、可回看编辑的训练记录。

            执行规则：
            1. 先 search_exercises 复用已有动作；确实没有时才 create_exercise，然后用返回的
               exercise_id 一次 create_workout 写入本次全部动作，不要一个动作调用一次。
            2. 组数、次数、重量、间歇、时长、RIR 只写用户明确给出或图片明确可读的值。没提到的字段
               必须省略，不能用常见值补齐，也不能写 0 代替未知。
            3. 自重动作不要编造外部重量；单侧动作按用户表述记录，不自行折算左右合计。
            4. 用户在纠正已有训练时，先 list_workouts 或 get_workout 找到目标记录，再用
               update_workout 修改，不要新建重复记录。
            5. 写入成功后最多两句说明，只补充结果卡看不到的信息（例如省略了哪些字段、需要用户确认
               什么），不复述已经在卡片里的数字。
            """
        }
    }

    func text(in defaults: UserDefaults = .standard) -> String {
        guard let customized = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !customized.isEmpty
        else {
            return defaultText
        }
        return customized
    }

    func isCustomized(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: defaultsKey) != nil
    }

    func save(_ text: String, in defaults: UserDefaults = .standard) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == defaultText {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(normalized, forKey: defaultsKey)
        }
    }

    func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    func markdown(in defaults: UserDefaults = .standard) -> String {
        """
        ---
        name: \(rawValue)
        description: \(summary)
        when_to_use: \(whenToUse)
        ---

        \(text(in: defaults))
        """
    }

    static func catalogPrompt(defaults: UserDefaults = .standard) -> String {
        let entries = AgentSkillRegistry.allDescriptors(defaults: defaults).map {
            "- name: \($0.id)\n  description: \($0.summary)\n  when_to_use: \($0.whenToUse)"
        }.joined(separator: "\n")
        return """
        ## 可用 Skills
        \(entries)

        目录只披露元数据。当前输入若已包含选中 Skill 全文，直接执行，不要重复加载；否则只在
        任务明显匹配且确实需要专业流程时渐进加载一次。不要臆造目录外 Skill。
        """
    }
}
