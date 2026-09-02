import Foundation
import SwiftOpenAI

extension AgentToolName {
    var chatTool: ChatCompletionParameters.Tool {
        ChatCompletionParameters.Tool(function: .init(
            name: rawValue,
            strict: true,
            description: toolDescription,
            parameters: toolParameters
        ))
    }

    private var toolDescription: String {
        switch self {
        case .searchExercises:
            "按名称搜索未归档动作，返回 exercise_id、target_kind 与 laterality；记录训练或计划前使用。"
        case .createExercise:
            "仅在动作库没有语义等价项时批量创建标准动作，并明确 target_kind 与 laterality。左右各做用 both；双侧同时或不区分用 none。"
        case .updateExercise:
            "按 Int64 exercise_id 修正动作名称、完成方式或侧别；只提交有明确用户或本次训练证据的字段。"
        case .archiveExercise:
            "按 Int64 exercise_id 归档动作；已有训练和计划关系保留。"
        case .mergeExercises:
            "把重复动作合并到目标动作，并重绑已有训练与计划关系。"
        case .listWorkouts:
            "按可选日期范围读取训练摘要；已预加载的当日记录无需重复读取。"
        case .getWorkout:
            "按 Int64 record_id 读取一条训练详情。"
        case .createWorkout:
            "一次创建一条或多条训练。必须显式给出 target_kind、laterality 和逐 effort evidence：‘左右各12次’用 laterality=both，并为同一 logical_set_index 各写 left/right；双腿同时才用 none。"
        case .deleteWorkout:
            "删除指定 Int64 训练记录；仅在当前用户消息明确授权删除时使用。"
        case .listMeals:
            "按可选日期范围读取饮食摘要；已预加载的当日记录无需重复读取。"
        case .getMeal:
            "按 Int64 record_id 读取一条饮食详情。"
        case .createMeal:
            "创建一餐新记录；同一轮可多次调用，每次都新增。未知营养字段省略。纠正、补图或同一餐新视角必须先读取再用 update_meal，不要用本工具代替更新。"
        case .deleteMeal:
            "删除指定 Int64 饮食记录；仅在当前用户消息明确授权删除时使用。"
        case .listBodyEntries:
            "按可选日期范围读取体重与体态摘要；已预加载的近期记录无需重复读取。"
        case .getBodyEntry:
            "按 Int64 record_id 读取一条身体记录详情。"
        case .createBodyEntry:
            "创建一条新的体重或体态记录；同一轮可多次写入，每次都新增。不得从外观猜数值。补充已有记录的多角度照片必须先读取再用 update_body。"
        case .deleteBodyEntry:
            "删除指定 Int64 身体记录；仅在当前用户消息明确授权删除时使用。"
        case .listPrograms:
            "读取可执行训练计划摘要。"
        case .getProgram:
            "按 Int64 program_id 读取计划概览和独立逐组处方。"
        case .createProgram:
            "创建训练计划；每个动作必须使用有效 Int64 exercise_id，并以独立逐组处方表达左右、次数或时长。若计划由当日已有训练总结而来，必须传入这些记录的 source_workout_record_ids，让本机同时保存一次已完成的计划执行。"
        case .updateProgram:
            "用完整独立逐组处方直接更新已有计划；已开始的 Session 继续使用自己的处方快照。"
        case .archiveProgram:
            "归档训练计划，保留训练历史。"
        case .deleteProgram:
            "永久删除训练计划；仅在当前用户消息明确授权时使用，训练历史保留。"
        case .startProgram:
            "按 Int64 program_id 创建不可变训练 Session 并开始带练。"
        case .loadSkill:
            "按需加载一项专业健身 Skill 的完整 Markdown 指令。可用 Skill：\(AgentSkill.catalogForToolDescription)。"
        case .updateWorkout:
            "按 record_id 更新一条训练并复述明确 target_kind/laterality；左右 evidence 与侧别冲突会返回字段错误。"
        case .updateMeal:
            "按 list_meals 或 get_meal 返回的 Int64 record_id 更新一条饮食记录，并把本次新媒体合并到原记录。用户纠正食材、餐名或营养估算时优先使用。"
        case .updateBody:
            "按 list_body_entries 或 get_body_entry 返回的 Int64 record_id 更新一条身体记录，并把本次新媒体合并到原记录。不得补写没有证据的指标。"
        case .updateGym:
            """
            新建或更新电子健身房及其可见器械，并把本次用于识别的照片保存到健身房档案。\
            未指定 gym_name 时更新当前健身房。若历史消息明确标记可引用紧邻上一轮的健身房\
            图片，必须传 media_source=recent_gym_turn；不得引用更早或无关媒体。
            """
        case .switchGym:
            "把一个已经存在或明确命名的健身房设为当前健身房。"
        case .recordPerformanceAnalysis:
            "把用户主动请求的视频复盘保存到指定 Performance。只记录画面可见证据、明确局限和一般训练建议；不得诊断伤病或修改训练事实。"
        case .submitFeedback:
            "向 Soma 维护者提交产品反馈。只有当前用户消息明确要求提交产品反馈时才能调用；发送内容固定为当前消息原文和当前附件，不得用于动作评价、饮食建议、身体观察或一般教练反馈。"
        }
    }

    private var toolParameters: JSONSchema {
        switch self {
        case .searchExercises:
            object([
                "query": string("动作名称或同义搜索词"),
                "target_kind": string(
                    "完成方式筛选",
                    values: WorkoutTargetKind.allCases.map(\.rawValue)
                ),
                "laterality": string(
                    "侧别筛选：none=双侧同时或不区分，both=左右分别，left/right=仅单侧",
                    values: ExerciseLaterality.allCases.map(\.rawValue)
                ),
                "limit": integer("最多返回多少条，默认 10，最大 20")
            ], required: ["query"])
        case .createExercise:
            object([
                "exercises": array(
                    object([
                        "exercise_name": string("简洁、明确的标准动作名称"),
                        "target_kind": string(
                            "repetitions=按次数，duration=按时长",
                            values: WorkoutTargetKind.allCases.map(\.rawValue)
                        ),
                        "laterality": string(
                            "none=双侧同时或不区分，both=左右分别，left/right=仅单侧",
                            values: ExerciseLaterality.allCases.map(\.rawValue)
                        )
                    ], required: ["exercise_name", "target_kind", "laterality"]),
                    description: "一次创建 1 到 20 个动作；已存在名称返回原 exercise_id 并以明确证据更新完成方式与侧别"
                )
            ], required: ["exercises"])
        case .updateExercise:
            object([
                "exercise_id": integer("要更新的动作 Int64 ID"),
                "exercise_name": string("新的标准动作名称；不改名时省略"),
                "target_kind": string(
                    "修正后的完成方式",
                    values: WorkoutTargetKind.allCases.map(\.rawValue)
                ),
                "laterality": string(
                    "修正后的侧别",
                    values: ExerciseLaterality.allCases.map(\.rawValue)
                )
            ], required: ["exercise_id"])
        case .archiveExercise:
            object([
                "exercise_id": integer("要归档的动作 Int64 ID")
            ], required: ["exercise_id"])
        case .mergeExercises:
            object([
                "exercise_id": integer("要合并并归档的来源动作 Int64 ID"),
                "target_exercise_id": integer("保留的目标动作 Int64 ID")
            ], required: ["exercise_id", "target_exercise_id"])
        case .listWorkouts, .listMeals, .listBodyEntries:
            object([
                "date_from": string("ISO8601 或 yyyy-MM-dd 起始日期（含）"),
                "date_to": string("ISO8601 或 yyyy-MM-dd 结束日期（含）"),
                "sort": string("排序", values: ["newest", "oldest"]),
                "limit": integer("最多返回多少条，默认 3，最大 10")
            ])
        case .getWorkout, .getMeal, .getBodyEntry:
            object([
                "record_id": integer("记录 Int64 ID")
            ], required: ["record_id"])
        case .deleteWorkout, .deleteMeal, .deleteBodyEntry:
            object([
                "record_id": integer("要删除的记录 Int64 ID")
            ], required: ["record_id"])
        case .loadSkill:
            object(
                ["skill_id": string(
                    "要加载的 Skill ID",
                    values: AgentSkillRegistry.allDescriptors().map(\.id)
                )],
                required: ["skill_id"]
            )
        case .listPrograms:
            object([:])
        case .getProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .createWorkout:
            object([
                "workouts": workoutCreateItems()
            ], required: ["workouts"])
        case .createMeal:
            object([
                "occurred_at": string("可选 ISO-8601 发生时间；省略时使用当前 Job 冻结的默认记录时间"),
                "meal_type": string("仅在用户明确说出餐次时填写：早餐、午餐、下午点心、晚餐或加餐"),
                "title": string("食物或餐食名称"),
                "calories": integer("估算千卡"),
                "protein": number("蛋白质克数"),
                "carbs": number("碳水克数"),
                "fat": number("脂肪克数"),
                "glycemic_speed": string(
                    "基于食物组成的定性消化吸收速度，不是个体血糖预测",
                    values: MealGlycemicSpeed.allCases.map(\.rawValue)
                ),
                "glycemic_assessment": string("简要说明判断依据与不确定性，不给出血糖峰值或诊断"),
                "recommended_eating_order": string("基于实际可见菜品给出简短食用顺序，用箭头连接；证据不足时省略"),
                "items": mealItemArray(),
                "note": string("估算依据、不确定性或用户原始补充")
            ], required: ["title"])
        case .createBodyEntry:
            object([
                "occurred_at": string("可选 ISO-8601 发生时间；省略时使用当前 Job 冻结的默认记录时间"),
                "weight": number("明确读到或用户提供的体重 kg"),
                "body_fat": number("明确读到或用户提供的体脂率"),
                "waist": number("明确读到或用户提供的腰围 cm"),
                "posture_note": string("中性、非诊断的可见体态观察"),
                "safety_note": string("局限性与安全提醒")
            ])
        case .updateWorkout:
            object([
                "record_id": integer("训练记录 Int64 ID"),
                "occurred_at": string("仅在用户明确纠正时间时提供的 ISO-8601 发生时间"),
                "exercise_id": integer("修正后动作 Int64 ID"),
                "target_kind": string(
                    "本次记录的明确完成方式",
                    values: WorkoutTargetKind.allCases.map(\.rawValue)
                ),
                "laterality": string(
                    "本次记录的明确侧别；左右各做必须为 both",
                    values: ExerciseLaterality.allCases.map(\.rawValue)
                ),
                "set_entries": workoutSetEntries(
                    "替换后的完整有序组；不修改组数据时省略"
                ),
                "rest_seconds": integer("修正后的组间休息秒数"),
                "duration_minutes": integer("修正后的训练时长分钟数"),
                "form_score": integer("有充分视频证据时的动作评分"),
                "intensity": string("有证据的负荷判断"),
                "feedback": string("有证据的动作反馈")
            ], required: ["record_id", "target_kind", "laterality"])
        case .updateMeal:
            object([
                "record_id": integer("饮食记录 Int64 ID"),
                "occurred_at": string("仅在用户明确纠正时间时提供的 ISO-8601 发生时间"),
                "meal_type": string("早餐、午餐、下午点心、晚餐或加餐"),
                "title": string("修正后的食物或餐食名称"),
                "calories": integer("修正后的估算千卡"),
                "protein": number("修正后的蛋白质克数"),
                "carbs": number("修正后的碳水克数"),
                "fat": number("修正后的脂肪克数"),
                "glycemic_speed": string(
                    "修正后的定性消化吸收速度，不是个体血糖预测",
                    values: MealGlycemicSpeed.allCases.map(\.rawValue)
                ),
                "glycemic_assessment": string("修正后的判断依据与不确定性"),
                "recommended_eating_order": string("修正后的简短食用顺序；证据不足时省略"),
                "items": mealItemArray(),
                "note": string("修正依据、不确定性或用户原始补充")
            ], required: ["record_id"])
        case .updateBody:
            object([
                "record_id": integer("身体记录 Int64 ID"),
                "occurred_at": string("仅在用户明确纠正时间时提供的 ISO-8601 发生时间"),
                "weight": number("明确读到或用户提供的体重 kg"),
                "body_fat": number("明确读到或用户提供的体脂率"),
                "waist": number("明确读到或用户提供的腰围 cm"),
                "posture_note": string("中性、非诊断的可见体态观察"),
                "safety_note": string("局限性与安全提醒")
            ], required: ["record_id"])
        case .updateGym:
            object([
                "gym_name": string("场馆名称；省略则使用当前健身房"),
                "summary": string("与训练有关的环境总结"),
                "media_source": string(
                    "可选的照片来源声明；明确继续紧邻上一轮图片时选 recent_gym_turn",
                    values: ["current_turn", "recent_gym_turn"]
                ),
                "equipment": array(
                    object([
                        "name": string("器械名称"),
                        "category": string("力量、有氧、自由重量或功能训练"),
                        "capabilities": string("可支持的动作或肌群"),
                        "confidence": number("识别置信度 0 到 1")
                    ], required: ["name", "category", "capabilities"]),
                    description: "画面中可见的器械，合并重复视角"
                )
            ])
        case .switchGym:
            object(["gym_name": string("目标健身房名称")], required: ["gym_name"])
        case .createProgram:
            object([
                "program_name": string("训练计划名称"),
                "overview": string("用户明确提供、可编辑的计划概览"),
                "schedule_hint": string("用户明确提供的安排提示"),
                "source_workout_record_ids": array(
                    integer("当日已有训练的 record_id"),
                    description: "仅在基于当日已有训练总结计划时提供；按原训练顺序，至少一条"
                ),
                "template_exercises": templateExerciseArrayV3()
            ], required: ["program_name", "template_exercises"])
        case .updateProgram:
            object([
                "program_id": integer("训练计划 Int64 ID"),
                "program_name": string("更新后的训练计划名称；省略则保持不变"),
                "schedule_hint": string("用户明确提供的安排提示"),
                "template_exercises": templateExerciseArrayV3()
            ], required: ["program_id", "template_exercises"])
        case .archiveProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .deleteProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .startProgram:
            object([
                "program_id": integer("训练计划 Int64 ID"),
                "auto_recording_policy": string(
                    "本次明确选择的录像策略；省略则关闭",
                    values: ["disabled", "one_per_exercise", "every_set"]
                )
            ], required: ["program_id"])
        case .recordPerformanceAnalysis:
            object([
                "performance_id": integer("Performance Int64 ID"),
                "input_fingerprint": string("当前复盘任务明确提供的输入指纹"),
                "evidence": string("按动作阶段描述的可见画面证据"),
                "limitations": string("镜头、遮挡、采样或缺失阶段造成的局限"),
                "feedback": string("中性、可执行、非诊断的一般训练建议")
            ], required: [
                "performance_id",
                "input_fingerprint",
                "evidence",
                "limitations",
                "feedback"
            ])
        case .submitFeedback:
            object([:])
        }
    }

    private func object(
        _ properties: [String: JSONSchema],
        required: [String] = []
    ) -> JSONSchema {
        JSONSchema(
            type: .object,
            properties: properties,
            required: required.isEmpty ? nil : required,
            additionalProperties: false
        )
    }

    private func mealItemArray() -> JSONSchema {
        array(
            object([
                "id": string("更新已有食物项时使用的稳定 UUID"),
                "name": string("食物名称"),
                "portion_description": string("份量说明"),
                "calories": integer("分项千卡"),
                "protein": number("分项蛋白质克数"),
                "carbs": number("分项碳水克数"),
                "fat": number("分项脂肪克数")
            ], required: ["name"]),
            description: "有序食物项；未知营养字段省略"
        )
    }

    private func string(_ description: String, values: [String]? = nil) -> JSONSchema {
        JSONSchema(type: .string, description: description, enum: values)
    }

    private func integer(_ description: String) -> JSONSchema {
        JSONSchema(
            type: .integer,
            description: "\(description)。请传 JSON integer，不要加引号或单位"
        )
    }

    private func number(_ description: String) -> JSONSchema {
        JSONSchema(
            type: .number,
            description: "\(description)。请传 JSON number，不要加引号或单位；1/3 先换算为 0.333"
        )
    }

    private func array(_ items: JSONSchema, description: String) -> JSONSchema {
        JSONSchema(type: .array, description: description, items: items)
    }

    private func workoutSetEntries(_ description: String) -> JSONSchema {
        array(
            object([
                "logical_set_index": integer("从 1 开始的逻辑组序号；左右两侧使用相同序号"),
                "side": string(
                    "none=双侧同时或不区分，left/right=对应单侧 effort",
                    values: WorkoutEffortSide.allCases.map(\.rawValue)
                ),
                "target_kind": string(
                    "repetitions 只填 reps；duration 只填 duration_seconds",
                    values: WorkoutTargetKind.allCases.map(\.rawValue)
                ),
                "reps": integer("该组明确完成的次数"),
                "duration_seconds": integer("按时长动作该组明确完成的秒数；与 reps 二选一"),
                "external_weight_kg": number("该组外部负重 kg；明确自重时填 0"),
                "rest_seconds": integer("该 effort 之后实际或明确提供的间歇秒数")
            ], required: ["logical_set_index", "side", "target_kind"]),
            description: description
        )
    }

    private func workoutCreateItems() -> JSONSchema {
        array(
            object([
                "exercise_id": integer("必须存在且未归档的动作 Int64 ID"),
                "target_kind": string(
                    "本次记录的明确完成方式",
                    values: WorkoutTargetKind.allCases.map(\.rawValue)
                ),
                "laterality": string(
                    "none=双侧同时或不区分；both=左右分别；left/right=仅单侧",
                    values: ExerciseLaterality.allCases.map(\.rawValue)
                ),
                "occurred_at": string("可选带时区 ISO-8601 发生时间；省略时使用 Job 冻结的默认记录时间"),
                "set_entries": workoutSetEntries(
                    "按实际顺序保存每组事实；次数或重量未知时省略对应字段"
                ),
                "rest_seconds": integer("用户明确提供的组间休息秒数"),
                "duration_minutes": integer("用户明确提供的训练时长分钟数"),
                "form_score": integer("有充分视频证据时的动作评分"),
                "intensity": string("有证据的负荷判断"),
                "feedback": string("有证据的动作反馈")
            ], required: ["exercise_id", "target_kind", "laterality", "set_entries"]),
            description: "一次课的多条训练记录，每条绑定已有动作 ID；不要指定 record_id。最多 20 条。"
        )
    }

    private func templateExerciseArrayV3() -> JSONSchema {
        array(
            object([
                "exercise_id": integer("动作 Int64 ID，必须大于 0"),
                "order": integer("从 1 开始且不重复的动作顺序"),
                "laterality": string(
                    "none=左右同时或不区分；both=先左后右；left/right=仅单侧",
                    values: ExerciseLaterality.allCases.map(\.rawValue)
                ),
                "target_rest_seconds": integer("动作各组之间的统一间歇，0 到 3600 秒"),
                "rest_between_sides_seconds": integer("左右分开动作统一换侧间歇，0 到 3600 秒；仅 both 可用"),
                "equipment_kind": string("用户明确指定的必要器械"),
                "notes": string("用户明确提供的动作备注"),
                "set_prescriptions": array(
                    object([
                        "order": integer("从 1 开始且不重复的逻辑组顺序"),
                        "kind": string(
                            "组类型",
                            values: [WorkoutSetKind.warmup.rawValue, WorkoutSetKind.working.rawValue]
                        ),
                        "target_kind": string(
                            "目标类型；repetitions 只提供 target_reps，duration 只提供 target_duration_seconds",
                            values: WorkoutTargetKind.allCases.map(\.rawValue)
                        ),
                        "target_reps": integer("次数目标，1 到 1000"),
                        "target_duration_seconds": integer("时长目标秒数，1 到 86400"),
                        "target_weight_kg": number("不区分侧别或双侧共用的外部重量，0 到 1000 kg"),
                        "left_weight_kg": number("左侧外部重量，0 到 1000 kg"),
                        "right_weight_kg": number("右侧外部重量，0 到 1000 kg"),
                        "notes": string("本组备注")
                    ], required: ["order", "kind", "target_kind"]),
                    description: "每组互相独立；至少一组"
                )
            ], required: ["exercise_id", "order", "laterality", "set_prescriptions"]),
            description: "按顺序排列的动作；每个动作包含独立逻辑组"
        )
    }
}
