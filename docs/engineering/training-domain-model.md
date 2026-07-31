# 训练领域模型与运行时协议

- 状态：已采纳设计，待实现
- 日期：2026-07-31
- 上游依据：
  - [ADR 0028](../adr/0028-semantic-exercise-identity.md)
  - [ADR 0029](../adr/0029-versioned-training-plans-and-session-facts.md)
  - [ADR 0030](../adr/0030-deterministic-guided-workout-and-session-recording.md)
- 关联：[PRD 010](../prd/010-exercise-library-plans-guided-training.md)

本文固定动作身份、计划、训练事实、带练和录像的实现合同。字段名可以在 Swift 中按语言习惯
调整，但身份、真值、引用和生命周期语义不得漂移。

## 领域边界

```text
ExerciseDefinition
  ├─ ExerciseContent
  ├─ ExerciseMedia
  ├─ WorkoutEntry（旧聚合历史）
  ├─ TemplateExercise
  └─ ExercisePerformance

TrainingProgram
  └─ WorkoutTemplateVersion
       └─ TemplateExercise
            ↓ 开始时快照
WorkoutSession
  └─ ExercisePerformance
       └─ WorkoutSet
```

- `ExerciseDefinition` 是动作身份事实。
- `WorkoutTemplateVersion` 是可修改的计划处方。
- `WorkoutSession` 是一次执行容器。
- `WorkoutSet.actual*` 是完成统计的事实。
- `RecommendationSnapshot` 是建议，不是计划或实际结果。

## SwiftData 目标模型

### `ExerciseDefinition`

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `id` | UUID | 稳定、不可改 |
| `canonicalName` | String | 当前数据空间规范化后唯一 |
| `movementPattern` | String? | 用户或内容元数据，缺失为空 |
| `equipmentKind` | String? | 不参与本地语义去重 |
| `laterality` | enum? | bilateral/left/right/alternating |
| `angleOrVariation` | String? | 只保存明确事实 |
| `status` | enum | active/archived |
| `createdAt/updatedAt` | Date | 本地时间事实 |

名称唯一性只防止并发产生完全相同标准名称，不承担同义判断。归档动作保留历史，但默认不进入
输入候选；Agent Tool 可以返回归档标记前先由产品规则决定是否需要恢复。

### `ExerciseMergeRecord`

保存 `sourceExerciseID`、`targetExerciseID`、迁移引用清单、时间与撤销状态。一次合并必须在一个
SwiftData transaction 内迁移：

- `WorkoutEntry.exerciseID`；
- `TemplateExercise.exerciseID`；
- `ExercisePerformance.exerciseID`；
- `ExerciseContent`、`ExerciseMedia`；
- Recommendation target。

撤销仅保证最近一次、尚未发生冲突性后续编辑的合并；无法安全撤销时提示用户，不猜测拆分。

### 内容与媒体

`ExerciseContent` 保存可编辑提示、主要肌群、辅助肌群、动作模式、来源和版本。
`ExerciseMedia` 保存：

- `kind`: userDemo/somaOwned/licensed/externalLink；
- 本地 `MediaAttachmentReference` 或 HTTPS URL；
- `rightsNote`、`sourceTitle`、`sortOrder`；
- 创建、修改时间。

外部链接不是本地副本；链接失效不删除来源记录。多个内容版本通过显式版本或历史快照恢复，
不把每次 AI 生成直接覆盖成不可逆文本。

### 计划

`TrainingProgram` 保存名称、目标、状态和当前版本引用。

`WorkoutTemplateVersion` 保存：

- 稳定 template family ID；
- 单调 version；
- 名称与 schedule hint；
- 创建来源和时间；
- 是否为当前版本。

`TemplateExercise` 保存：

- `exerciseID`、顺序；
- 目标组数、次数、重量和间歇，缺失保持 `nil`；
- `firstSetIsWarmup`；
- 可选 progression rule 与用户备注。

任何处方字段改变都创建新版本。排序变化也属于版本变化。

### 执行事实

`WorkoutSession`：

- `id`、`startedAt`、`endedAt`；
- `gymID`；
- `sourceTemplateFamilyID` 与 version；
- 不可变 `prescriptionSnapshot`；
- `status`: draft/active/paused/completed/abandoned；
- 当前带练恢复位置；
- 来源 Turn/Job。

`ExercisePerformance`：

- `sessionID`、`exerciseID`、顺序；
- 本动作处方快照；
- 备注、录像引用和分析引用；
- 状态。

`WorkoutSet`：

| 类别 | 字段 |
| --- | --- |
| 身份 | `id`、`performanceID`、`order` |
| 类型 | warmup/working/drop/failure/custom |
| 侧别 | bilateral/left/right/alternating |
| 计划 | `plannedReps/Weight/Rest` |
| 实际 | `actualReps/Weight/Rest` |
| 状态 | pending/inProgress/completed/skipped/failed |
| 时间 | `startedAt/completedAt` |

只有 `completed` 且组数、次数、外部重量完整有效的实际值参与训练容量。计划值不得回填实际值。

### 旧记录兼容

1. 给现有 `WorkoutEntry` 增加可空 `exerciseID`。
2. 按现有名称生成迁移候选；无法可靠确认时保持空并等待 Agent/用户后续归一。
3. 不从聚合 `sets × reps × weight` 创建多条 `WorkoutSet`。
4. 新的自由聊天记录可以继续产生聚合 `WorkoutEntry`，并关联动作 ID。
5. 带练产生 Session/Performance/Set，不再额外创建等价 `WorkoutEntry`。
6. 统计层以来源 ID 去重后合并两种事实。

## 固定 Tool 协议

### `list_exercise_names`

请求参数为空：

```json
{}
```

响应：

```json
{
  "exercises": [
    {
      "id": "8FA0C452-DAF8-4A13-8295-462CDB6EFD91",
      "name": "单侧哑铃卧推"
    }
  ]
}
```

约束：

- 返回当前数据空间全部 active 动作，按名称稳定排序；
- 只有 `id` 和 `name`；
- 空动作库返回空数组；
- Tool 不接收查询词、不做搜索、不返回训练历史；
- Tool Schema 由 Runtime 固定。

### `record_workout` 与 `update_workout`

- 复用动作时：`exercise_id` 必填，Tool 忽略模型重复传来的展示名称。
- 新建动作时：`exercise_id` 为空且 `exercise_name` 必填。
- 两者同时缺失或同时表达冲突时返回 Tool error。
- 失效 ID 返回 `exercise_not_found`，错误中不暴露其他空间动作。
- Tool 成功结果返回最终 `exercise_id` 和 `workout_id`。
- 相同 Turn 与规范化参数继续由 `AgentMutationReceipt` 幂等。

### 计划 Tool

固定能力分为：

- `create_training_program`；
- `create_workout_template_version`；
- `update_workout_template`；
- `archive_training_program`；
- `query_user_data` 的 exercises/exercise_history/programs/templates/sessions scope。

Tool 只能创建和调整计划。开始 Session、完成 Set、控制相机和保存实际值由本地带练运行时处理，
不暴露为模型任意调用。

## 聊天快捷输入

输入候选完全本地执行：

1. 对 active `canonicalName` 做大小写、空白和本地化输入搜索；
2. 不调用模型，不创建或合并动作；
3. 点击动作只把标准名称填入草稿；
4. 随后查询该 ID 最近一条训练事实；
5. 生成可读候选，如“30 kg × 5 次 × 4 组，间歇 2 分钟”；
6. 只填充最近记录中非空字段；
7. 用户编辑或发送前不落业务数据。

最近记录的选择规则只有：同动作 ID、发生时间最新、没有被删除。第一版不比较疲劳、动作顺序、
计划来源或器械环境。

## 计划就绪检查

开始前只运行确定性规则：

- 模板至少有一个动作；
- 动作 ID 仍存在；
- 顺序没有重复；
- `firstSetIsWarmup == true` 且需要自动录像时存在第 2 组；
- 当前健身房缺少已知必要器械；
- 用户明确记录的不适/禁忌动作；
- 数值范围合法，但缺失值不自动补齐。

容量差异和训练负荷合理性不作为默认阻塞项。用户主动选择“优化本次训练”后，才创建
`RecommendationSnapshot`。

## 带练状态机

```text
ready
  → exerciseIntroduction
  → preSetCountdown
  → setInProgress
  → setConfirmation
  → resting
  → nextSet | nextExercise
  → sessionReview
  → completed
```

所有状态变化都保存 `sessionID + performanceID + setID` 恢复点。系统中断后：

- `inProgress` 且未确认的 Set 回到确认或重新开始，不自动完成；
- 休息可以根据持久开始时间重算剩余时间；
- 已确认实际值不丢失；
- abandoned 与 completed 是终态。

## 自动录像

`AutoRecordingPolicy` 属于当前 Session：

- `disabled`；
- `enabled`；
- `paused`；
- `cancelled`。

对每个 `ExercisePerformance` 只计算一次目标组：

```text
firstSetIsWarmup == false → order 1
firstSetIsWarmup == true  → order 2
```

相机流程：

1. 用户开启并完成预览；
2. 进入目标组倒计时后准备 capture session；
3. `setInProgress` 时开始写文件；
4. 用户确认、跳过、暂停或相机中断时停止；
5. 完成文件原子移入 `PrivateMedia` 并建立引用；
6. 每个动作只有一个 active performance video；重录替换引用后回收未共享旧文件。

默认无音轨。任何失败都产生可理解状态但不改变 Set 事实。

## AI 内容与复盘

- 动作说明和建议按用户请求生成，并保存输入指纹。
- 训练完成时先由本地规则生成完成组、容量、偏差、跳过和休息摘要。
- 用户选择具体 Performance 视频后才创建分析 Job。
- 远程输入明确列出视频或关键帧、动作身份、相关历史和用户主观反馈。
- 反馈绑定 `performanceID`，包含证据、局限、创建时间和可编辑文本。
- 删除分析不删除原视频；删除视频不伪造分析仍有完整证据。

## 数据主权

- 新模型进入加密备份与恢复 DTO。
- 开放导出至少覆盖动作标准名称、训练 Session、实际 Set 和用户选择的训练媒体。
- 合并日志与 Recommendation 是否进入开放导出由格式版本明确，不能泄露内部 Trace。
- 清除个人数据删除个人空间模型及未共享媒体。
- 远程分析素材遵守 PRD 011 的最小上传和保留规则。

## 验证矩阵

| 层 | 必须覆盖 |
| --- | --- |
| Model | 名称唯一、ID 引用、版本快照、Set 真值、级联删除 |
| Tool | ID/name 协议、失效 ID、跨空间、幂等、计划版本 |
| Migration | 旧记录不丢失、不虚构 Set、统计不重复 |
| Candidate | 本地搜索、最近值、nil、只修改草稿 |
| Coordinator | 暂停、恢复、跳过、替换、异常退出 |
| Camera | 权限、目标组、中断、重录、磁盘、热压力 |
| Privacy | 远程选择、无麦克风、备份、恢复、清除 |
| UI | VoiceOver、Dynamic Type、键盘、长名称、空态 |
