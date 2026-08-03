# 训练领域模型与运行时协议

- 状态：已实现协议
- 日期：2026-07-31
- 上游依据：
  - [ADR 0028](../adr/0028-semantic-exercise-identity.md)
  - [ADR 0029](../adr/0029-versioned-training-plans-and-session-facts.md)
  - [ADR 0030](../adr/0030-deterministic-guided-workout-and-session-recording.md)
  - [ADR 0035](../adr/0035-silent-bundled-exercise-content-and-on-demand-images.md)
  - [ADR 0038](../adr/0038-focused-guided-workout-and-capture-geometry.md)
  - [PRD 013](../prd/013-guided-workout-experience-and-capture.md)
- 关联：[PRD 010](../prd/010-exercise-library-plans-guided-training.md)

本文固定动作身份、计划、训练事实、带练和录像的实现合同。字段名可以在 Swift 中按语言习惯
调整，但身份、真值、引用和生命周期语义不得漂移。

## 领域边界

```text
ExerciseDefinition
  ├─ ExerciseContent / BundledExerciseContent（仅缺失字段按需关联）
  ├─ ExerciseMedia / ExerciseImageReference
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

#### 静默内置目录

`BundledExerciseCatalog` 是只读 App 资源，不是 SwiftData 模型，也不是个人动作库：

- 可以预置标准名称、目录别名、基础说明、通用肌群和包内图片资源名；
- App 启动只遍历已存在的 `ExerciseDefinition` 做 fill-only 激活，绝不按目录创建动作；目录版本
  可以替换旧 bundled 图片引用，但不得覆盖 generated/user 图片；
- 新动作创建或改名后可做一次确定性目录查找；目录别名只用于内容关联，不参与 Agent 语义身份；
- `list_exercise_names`、聊天候选与动作列表只读取 active `ExerciseDefinition`；
- 包内资源不复制到 `PrivateMedia`，不进入个人备份或开放导出。

`ExerciseImageReference` 保存：

| 字段 | 规则 |
| --- | --- |
| `kind` | `actionIllustration` 或 `muscleMap` |
| `source` | `bundled`、`generated` 或 `user` |
| `resourceName` | 仅 bundled 使用，指向 App 包资源 |
| `localPath` | 仅 generated/user 使用，指向 `PrivateMedia` |
| `title/createdAt` | 可审查展示与排序 |

generated/user 图片参与动作合并与撤销、媒体引用回收、加密备份恢复和个人数据清除。内置图
不可从个人记录中物理删除，但用户图片和生成图可以删除或替换。

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
- 休息目标结束时间 `restTargetEndAt`，用于前后台和重启后按绝对时间恢复；
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
  → resting | setConfirmation（仅中断恢复或显式纠错）
  → nextSet | nextExercise
  → sessionReview
  → completed
```

`preSetCountdown` 的可见组件拥有基于 `phaseStartedAt + 3 秒` 的截止时间任务；它不能依赖外层
View 是否因 SwiftData 字段变化而重建。截止后只在 Session 仍处于倒计时阶段时进入
`setInProgress`，因此页面取消和重复回调都不会重复启动同一组。`setInProgress` 先保存并投影，
相机准备和开始在专用队列继续；相机不能成为训练界面出现的前置条件。

所有状态变化都保存 `sessionID + performanceID + setID` 恢复点。系统中断后：

- `inProgress` 且未确认的 Set 回到确认或重新开始，不自动完成；
- 休息根据持久 `restTargetEndAt` 重算剩余时间，`±15 秒`直接调整目标结束时间；
- 已确认实际值不丢失；
- abandoned 与 completed 是终态。

## 自动录像

`AutoRecordingPolicy` 属于当前 Session：

- `disabled`；
- `enabled`：每个动作录首个工作组，兼容既有持久值；
- `everySet`：每一组都录；
- `paused`；
- `cancelled`。

对每个 `ExercisePerformance` 只计算一次目标组：

```text
firstSetIsWarmup == false → order 1
firstSetIsWarmup == true  → order 2
```

非自动目标组仍可由用户点击“录制本组”。相机流程：

1. `setInProgress` 根据 policy 或手动操作发起录像请求，之前不准备相机；
2. `prepare`、`startRunning` 和 `startRecording` 在专用队列执行，训练事实先保存；
3. 只有 `didStartRecordingTo` 回调后才把录像标为 active 并展示取景器；
4. 用户确认、跳过、暂停或相机中断时停止；
5. 完成文件原子移入 `PrivateMedia`，写入当前 `WorkoutSet.recordedVideoPath`；
6. `ExercisePerformance.activeVideoPath` 保留第一段作为旧复盘入口，逐组引用保存全部录像。

预览和保存文件共享 `WorkoutCaptureGeometry`：

- `AVCaptureDevice.RotationCoordinator` 分别提供 horizon-level preview/capture 角度；
- Rotation Coordinator 在 Capture Session 准备后创建，不依赖 SwiftUI 预览先出现；
- 紧凑小窗使用 `.resizeAspectFill` 贴合窗口并允许边缘裁切，放大取景使用 `.resizeAspect` 展示
  完整画幅；
- 预览与 Movie Output 显式采用相同镜像策略；
- 开始录像时锁定本段方向、角度和镜像，停止后再恢复设备方向监听；
- 带练可使用 portrait、landscape left/right，其他 App 页面保持 portrait；
- 进入带练时请求 Scene 刷新，取消或结束后恢复 portrait；
- 紧凑小窗和放大取景只切换 SwiftUI 投影，共享同一个 Capture Session、Movie Output 和由相机
  服务持有的 `AVCaptureVideoPreviewLayer`；旧 Host 清理不能移除已经挂入新 Host 的同一层。
- `previewing` 不是用户可见录像事实；只有 `recording` 可显示和放大相机，停止或失败立即回到
  普通带练界面。
- 预览容器的横竖比例读取当前 Scene 尺寸，不能读取录像期间锁定的 `Capture Geometry`；设备
  方向变化向 Scene 请求精确方向。竖屏和横屏都优先扩大相机区域，控制信息只占完成当前组所需空间。
- `startRunning`、`startRecording`、`stopRecording` 和相机状态读取进入同一串行队列，不占用
  Main Actor；重复相机准备合并为同一个任务。

默认无音轨。任何失败都产生可理解状态但不改变 Set 事实。

语音提示由阶段事件驱动，覆盖动作进入、准备组、`3/2/1`、开始组、完成与休息、后续组和训练
完成；新阶段会取消过期播报，避免迟到或重复。Session Review 由本地事实生成时长、完成/跳过组、
有效容量、录像数和动作明细，不自动调用模型。删除 Session 时显式删除 Performance、Set、分析
和对应私有录像。

训练 Live Activity 与休息通知只保存 Session ID、通用阶段、完成/总组数和可选休息结束时间，
不展示动作名称、重量、用户文字或媒体；点击后通过 `soma://workout/session/{id}` 回到对应 Session。

## AI 内容与复盘

- 动作说明和建议按用户请求生成，并保存输入指纹。
- 图片生成是独立的显式用户操作：动作图和肌群图分别调用标准 Provider 的 image model；请求
  只使用动作标准名称、已保存的通用肌群/动作模式和绘图约束。
- 图片生成不会因打开详情、记录训练、计划就绪检查或带练启动而发生；成功数据先写入
  `PrivateMedia` 再原子关联，保存失败时回收文件。
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
| Catalog/Image | 空库静默、按动作激活、fill-only、资源加载、显式生成、上传、删除、合并与备份 |
| Coordinator | 暂停、恢复、跳过、替换、异常退出 |
| Camera | 权限、目标组、中断、重录、磁盘、热压力 |
| Privacy | 远程选择、无麦克风、备份、恢复、清除 |
| UI | VoiceOver、Dynamic Type、键盘、长名称、空态 |
