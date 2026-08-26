# 训练领域模型与运行时协议

- 状态：独立组、Effort、attempt 与自动收口实施中；SwiftData 打开路径见 ADR 0075，侧别与完成方式见 ADR 0076
- 日期：2026-08-16
- 上游依据：
  - [ADR 0028](../archive/0.0.1/adr/0028-semantic-exercise-identity.md)
  - [ADR 0029](../archive/0.0.1/adr/0029-versioned-training-plans-and-session-facts.md)
  - [ADR 0030](../archive/0.0.1/adr/0030-deterministic-guided-workout-and-session-recording.md)
  - [ADR 0035](../archive/0.0.1/adr/0035-silent-bundled-exercise-content-and-on-demand-images.md)
  - [ADR 0038](../archive/0.0.1/adr/0038-focused-guided-workout-and-capture-geometry.md)
  - [ADR 0060](../archive/0.0.5/adr/0060-guided-performance-workout-entry-projection.md)
  - [ADR 0071](../archive/0.0.6/adr/0071-integer-business-identities-and-explicit-relations.md)
  - [ADR 0073](../archive/0.0.7/adr/0073-independent-set-prescriptions-efforts-and-guided-finalization.md)
  - [ADR 0075](../archive/0.0.7/adr/0075-current-swiftdata-schema-without-historical-versions.md)
  - [ADR 0076](../archive/0.0.7/adr/0076-exercise-owned-laterality-and-target-kind.md)
  - [ADR 0086](../archive/0.0.8/adr/0086-preview-and-history-thumbs-use-aspect-fill.md)
  - [ADR 0090](../archive/0.0.9/adr/0090-current-state-business-models-and-session-facts.md)
  - [ADR 0000](../adr/0000-origin-through-0.0.11.md) 的动作级计划间歇收口
  - [PRD 013](../archive/0.0.1/prd/013-guided-workout-experience-and-capture.md)
  - [PRD 026](../archive/0.0.5/prd/026-guided-workout-record-projection-camera-failures-and-session-entry.md)
  - [PRD 031](../archive/0.0.7/prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
  - [PRD 035](../archive/0.0.9/prd/035-guided-preview-then-record-and-immediate-share.md)
  - [PRD 000](../prd/000-origin-through-0.0.11.md) 的动作级计划间歇收口
- 关联：[PRD 010](../archive/0.0.1/prd/010-exercise-library-plans-guided-training.md)

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
  └─ TemplateExercise
       └─ TemplateSetPrescription（当前独立逻辑组）
       ↓ 开始时快照
WorkoutSession
  └─ ExercisePerformance
       ├─ WorkoutSet（逻辑组）
       │    └─ WorkoutEffort（none / left / right 原子执行）
       └─ WorkoutEntry（终态、至少一组完成时的可审查投影）
```

- `ExerciseDefinition` 是动作身份事实。
- `TrainingProgram` 直接拥有当前计划处方。
- `WorkoutSession` 是一次执行容器。
- `TemplateSetPrescription` 是目标独立的计划逻辑组；两类计划间歇是动作级执行节奏。
- `WorkoutSet` 是用户看到的逻辑组；`WorkoutEffort.actual*` 是左右、次数/时长和录像的原子事实。
- `WorkoutEntry` 是完成动作进入统一 CRUD、导出和趋势的业务投影，通过 Session/Performance 来源
  ID、唯一 projection key 和一对一关系与原始事实关联。
- `RecommendationSnapshot` 是建议，不是计划或实际结果。

## SwiftData 目标模型

### `ExerciseDefinition`

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `businessID` | Int64 | 当前数据空间内稳定、不可改；UUID 仅保留为迁移锚点 |
| `canonicalName` | String | 当前数据空间规范化后唯一 |
| `movementPattern` | String? | 用户或内容元数据，缺失为空 |
| `equipmentKind` | String? | 不参与本地语义去重 |
| `laterality` | enum? | 空为未配置；展示默认全身。取值 none/both/left/right |
| `targetKind` | enum? | 空为未配置；展示默认按次数。取值 repetitions/duration |
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
- `ExerciseMedia`；
- Recommendation target。

撤销仅保证最近一次、尚未发生冲突性后续编辑的合并；无法安全撤销时提示用户，不猜测拆分。

### 内容与媒体

`ExerciseContent` 是编辑和生成时使用的当前值对象；`ExerciseDefinition` 直接保存当前提示、主要
肌群、辅助肌群和动作模式。
`ExerciseMedia` 保存：

- `kind`: userDemo/somaOwned/licensed/externalLink；
- 本地 `MediaAttachmentReference` 或 HTTPS URL；
- `rightsNote`、`sourceTitle`、`sortOrder`；
- 创建、修改时间。

外部链接不是本地副本；链接失效不删除来源记录。动作内容编辑或 AI 生成直接更新当前值，不维护
内容修订数组或恢复入口。

#### 静默内置目录

`BundledExerciseCatalog` 是只读 App 资源，不是 SwiftData 模型，也不是个人动作库：

- 可以预置标准名称、目录别名、基础说明、通用肌群和包内图片资源名；
- App 启动只遍历已存在的 `ExerciseDefinition` 做 fill-only 激活，绝不按目录创建动作；目录版本
  可以替换旧 bundled 图片引用，但不得覆盖 generated/user 图片；
- 新动作创建或改名后可做一次确定性目录查找；目录别名只用于内容关联，不参与 Agent 语义身份；
- `search_exercises`、聊天候选与动作列表只读取 active `ExerciseDefinition`；
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

`TrainingProgram` 保存名称、可编辑 `overview`、状态、`scheduleHint` 与当前动作处方。旧 `goal`
只作为迁移来源，不形成第二份事实。计划不保存版本号、版本来源、差异摘要或恢复链。

`TemplateExercise` 保存动作关系、顺序、从 `ExerciseDefinition` 复制的 `lateralityRaw`、器械、动作
备注、动作级组间歇 `targetRestSeconds` 与换侧间歇 `restBetweenSidesSeconds`。用户面对的侧别在动作
定义上修改。laterality 只允许：

- `.none`：全身，不区分左右；
- `.both`：左右分别执行且固定先左后右；
- `.left/.right`：只执行对应一侧。

`targetSets/targetReps/targetWeightKG/firstSetIsWarmup` 只用于旧 Tool、旧备份和迁移兼容；当前组目标
读取持久的 `TemplateSetPrescription`，两类计划间歇读取 `TemplateExercise`。

每条 `TemplateSetPrescription` 保存：

| 类别 | 字段与规则 |
| --- | --- |
| 身份 | `id/businessID/templateExerciseID/order`；每组独立，复制后不共享默认值 |
| 类型 | `kindRaw`: warmup/working；旧枚举中的其他值继续兼容但本版编辑器不扩展 |
| 目标 | `targetKindRaw`: repetitions/duration；只允许对应的 reps 或 durationSeconds |
| 重量 | none/单侧使用 `targetWeightKG`；both 可用 `leftWeightKG/rightWeightKG` |
| 兼容间歇 | `restBetweenSidesSeconds/restAfterSetSeconds` 仅无损读取旧计划；当前新写入保持为空 |
| 备注 | 可选组备注，空字符串不能被理解为模型已知事实 |

任何动作、独立组或排序变化都直接更新当前计划。开始训练时将动作级间歇与独立组编码进
`TemplateExercisePrescription`；组间歇只编译到非最终 `WorkoutSet`，换侧间歇编译到 `.both` 的每个
逻辑组。之后修改计划不影响既有 Session。

### 执行事实

`WorkoutSession` 保存不可变处方快照、状态以及当前 `performance/set/effort`。V5 新增
`currentEffortID`、`phaseDeadlineAt` 与 `transitionRevision`；`restTargetEndAt` 继续用于兼容休息通知
和旧恢复路径。来源 Turn/Job、场馆、计划 ID/名称快照与开始/结束时间保持原语义。

`ExercisePerformance` 保存动作关系、顺序、本动作独立组快照、状态、备注和旧视频入口；
`projectedWorkout` 是终态业务投影的一对一关系，`workoutProjectionSuppressed` 继续表达用户明确
删除后不可复活。

`WorkoutSet` 表示逻辑组：

| 类别 | 字段与规则 |
| --- | --- |
| 身份/关系 | `id/businessID/performanceID/performance/order` |
| 类型 | `kindRaw`、`laterality`、`plannedTargetKindRaw` |
| 计划 | reps/duration/weight、组后 rest、both 的 sides rest；V4 字段继续兼容 |
| 实际 | V4 聚合 reps/duration/weight/rest；V5 新运行时以 Effort 为准 |
| 状态/时间 | pending/inProgress/completed/skipped/failed、startedAt/completedAt |
| 录像 | `recordedVideoPath` 只作为 V4 兼容投影，V5 事实归 Effort |

`WorkoutEffort` 表示原子执行：

| 类别 | 字段与规则 |
| --- | --- |
| 身份/关系 | `id/businessID/workoutSetID/workoutSet/order` |
| 侧别 | none/left/right；both 由同一 Set 下 left、right 两条表达 |
| 目标 | repetitions/duration，以及对应 planned reps/seconds/weight |
| 实际 | actual reps/seconds/weight/rest；缺失保持 `nil` |
| 状态/时间 | pending/inProgress/completed/skipped/failed、startedAt/completedAt |
| 录像 | 每条 Effort 自己的 `recordedVideoPath` |

只有 completed Effort 的有效实际次数与外部重量参与容量。duration Effort、计划值、跳过和失败
Effort 不被伪造成重量容量；逻辑组数按 Set 计算，不因 both 拥有两条 Effort 翻倍。

### 旧记录兼容

1. `WorkoutEntry` 保留旧 UUID `exerciseID` 迁移锚点，并增加可空 `sourceWorkoutSessionID` 与
   `sourcePerformanceID`；当前业务关系是必需的 `ExerciseDefinition` 对象引用。
2. 启动迁移按规范名回填关系；空名称或无法可靠确认的记录绑定明确标记的“待确认动作”，不能
   以无动作关系状态进入新运行时。
3. 不从聚合 `sets × reps × weight` 创建多条 `WorkoutSet`。
4. 新的自由聊天记录可以继续产生聚合 `WorkoutEntry`，但必须关联动作对象和 Int64 ID。
5. 带练动作全部 Set 都为 completed/skipped 且至少一组 completed 时，按完成组顺序物化一条
   `WorkoutEntry`；跳过组不复制，缺少实际值保持 `nil`，全跳过不创建空记录。
6. 启动回填和完成路径以 `sourcePerformanceID` 幂等；统计层优先读取投影记录，只有旧
   Performance 尚未投影时才回退原始 Set。
7. 用户单独删除投影训练记录时，来源 Performance 设置 `workoutProjectionSuppressed`；原始执行
   证据继续保留，确定性回填不得重新创建该记录。
8. V5 将旧动作级 `targetSets` 展开为独立组，旧 Session Set 展开为单个 `.none` Effort；不按
   动作名猜左右，不把旧次数猜成时长。
9. 旧运行时将休息存到下一组时，迁移只对可证明归属的顺序做左移；无法证明时保持 `nil`。
10. 非空旧 Session/Performance 快照无法解码时迁移失败，不能静默变成空处方。
11. 投影 `WorkoutEntry` 增加 `projectionKey` 和 `sourcePerformance` 关系。带练投影使用
    `guided-performance:<uuid>`，其余记录使用 `entry:<uuid>`。已安装 V5 unique 索引保留，
    启动迁移即使 marker 已完成也要先补齐空 key。重复旧投影只保留一条 canonical 关系，其他
    历史记录保留但不能继续冒充该 Performance 的唯一投影。
12. `WorkoutSetEvidence` 可保存 logicalSetIndex、side、kind、targetKind、reps/duration、外部重量、
    休息和录像路径；旧只有 reps/weight 的载荷继续可解码。

## 固定 Tool 协议

### 动作与训练记录

- `search_exercises(query)` 返回匹配 active 动作的 Int64 `exercise_id` 和标准名称；已由上下文
  注入的匹配动作不重复查询。
- 只有没有语义等价项时才调用 `create_exercise(exercise_names)`；一次最多 20 个名称，已存在
  名称复用原 ID。
- `create_workout` 接收 `workouts` 数组，每条必须带有效 `exercise_id`，不允许用名称隐式创建
  动作，也不允许指定 `record_id`。一次最多 20 条。每次数组项都新增记录，不按同一 Turn 合并。
- `update_workout` 按 Int64 `record_id` 原位修改；失效 ID 或跨数据空间关系返回结构化错误。
- create/update 可选 `occurred_at`；省略时使用原始 Turn 冻结的稳定默认时间。
- Tool 成功结果返回最终 `exercise_id` 和 `workout_id`；幂等签名包含两者和最终发生时间。

### 计划 Tool

固定能力分为：

- `list_programs`、`get_program`：按 Int64 ID 返回计划摘要与详情；
- `create_program`：创建当前计划，每个动作都必须绑定有效 Int64 `exercise_id`；
- `update_program`：按 `program_id` 直接替换当前名称、安排和完整动作处方；
- `archive_program`、`delete_program`：分别归档或在明确授权后永久删除计划；
- `start_program`：只接受列表返回的计划 ID，在设备本地创建不可变 Session 并打开带练。

V5 计划 Tool 在动作层表达 laterality 与两类间歇，嵌套 `set_prescriptions` 表达独立组的 target
kind、次数/时长、逐侧重量和备注。递归验证必须拒绝 unknown 字段、非法枚举/范围、非 both 的
换侧间歇和 reps/duration 同时有效。新调用只暴露
新 schema；已经持久化的旧 schema Tool Call/Checkpoint 由版本化 decoder 确定性展开，不能因为
升级丢失用户已授权工作。

Tool 可创建、调整计划和在用户明确意图下启动一次带练。完成 Set、控制相机和保存实际值继续由
本地带练运行时处理，不暴露为模型任意调用。

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
- 每个动作至少有一条有效独立组，order 不重复；
- repetitions/duration union 合法，both 的左右配置与间歇合法；
- 每动作首工作组自动录像时至少存在一条 `kind == working` 的逻辑组；
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
  → setInProgress（由 currentEffortID 指向当前原子执行）
  → resting（左右间歇或组间间歇）| setConfirmation（仅中断恢复或显式纠错）
  → nextSet | nextExercise
  → sessionReview（动作记录已收口后的本地分享预览）
  → completed
```

`preSetCountdown` 使用持久 `phaseDeadlineAt`；它不能只依赖外层 View 是否因 SwiftData 字段变化
而重建。截止后只有 Session 阶段、当前 Effort 与 `transitionRevision` 仍匹配时才能进入
`setInProgress`，因此页面取消和重复回调不会重复启动同一 Effort。状态机先保存执行事实，相机
准备和开始在专用队列继续；相机不能成为训练界面出现的前置条件。

所有状态变化都保存 `sessionID + performanceID + setID + effortID + transitionRevision` 恢复点。
deadline 到期只能在 revision 与当前阶段仍匹配时提交一次转换。系统中断后：

- `setInProgress` 且未确认的次数 Effort 回到确认或重新开始，不自动完成；
- 休息根据持久 deadline 重算剩余时间，`±15 秒`直接调整目标结束时间；归零自动进入下一 Effort
  或 Set 的三秒倒计时；
- duration Effort 到期自动保存实际秒数；repetitions Effort 继续等待用户确认；
- 已确认实际值不丢失；
- abandoned 与 completed 是终态。

## 自动录像

`AutoRecordingPolicy` 属于当前 Session：

- `disabled`；
- `enabled`：每个动作录首个工作组，兼容既有持久值；
- `everySet`：每一组都录；
- `paused`；
- `cancelled`。

对每个 `ExercisePerformance` 只计算一次目标逻辑组：

```text
plannedSets.first(where: kind == working)
```

主界面始终保留录像按钮；非自动目标 Effort 也可主动录像。相机流程：

1. 自动策略在动作介绍或组前倒计时 preflight 到 `.previewing`，取景可见但不写文件；
2. 倒计时归零先进入 `.setInProgress`，等待执行页预览宿主挂上后再 `startRecording`；
3. 只有 `didStartRecordingTo` 后才把录像标为 active 并显示红点；
4. 组或 Effort 结束时 `stopRecording` 并绑定当前 Effort。
   `prepare`、`startRunning` 和文件写入在专用队列执行，训练事实先保存；
5. 用户确认、跳过、暂停、后台或相机中断时终结 attempt；saved/failed/cancelled 只能提交一次；
6. `AVErrorRecordingSuccessfullyFinishedKey == true` 且文件有效时保留文件，即使 error 非空；
7. 完成文件原子移入 `PrivateMedia`，写入当前 `WorkoutEffort.recordedVideoPath`；
8. Coordinator 消费 attempt 终态并成为唯一 Alert 源；已终结 attempt 的 stop 幂等，不产生第二个
   `stop-missing`；
9. `WorkoutSet.recordedVideoPath` 与 `ExercisePerformance.activeVideoPath` 只保留兼容投影。

预览和保存文件共享 `WorkoutCaptureGeometry`：

- `AVCaptureDevice.RotationCoordinator` 分别提供 horizon-level preview/capture 角度；
- Rotation Coordinator 在 Capture Session 准备后创建，不依赖 SwiftUI 预览先出现；
- 紧凑小窗和放大取景都使用 `.resizeAspectFill` 按取景比例铺满并允许边缘裁切；完整原片在媒体查看器中 `scaledToFit` 查看；
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

语音提示由阶段事件驱动，并由同一个 `WorkoutPrescriptionFormatter` 描述动作组数和每组次数/
秒数；异构组逐组摘要，both 明确“左右各做，左侧先开始”。新阶段取消过期播报。

最后一个 Effort 结束后不等待“保存并结束”：先物化最后一条动作 `WorkoutEntry`，再验证全部
Performance 终态、完成 Session、结束系统投影并进入本地分享预览。任一步失败保留已保存事实并
可重试，不提前展示成功页。删除带练 Session 时显式删除 Performance、Set、Effort、分析、
`guided-performance:` 投影记录和对应私有录像；从当日原始训练组装的完成 Session 只解除
`entry:` 原始记录的执行关系，不能删除用户原始记录。

## 动作记录与热量收口

- Performance 全部 Effort 终态且至少一个完成时创建唯一 `WorkoutEntry`；全跳过不建空记录。
- 投影按 Effort 写 `WorkoutSetEvidence`，保留逻辑组索引、侧别、次数/时长、重量、休息和录像。
- 投影在同一事务分配 business ID、绑定动作关系、设置 projection key 和一对一关系；删除 suppression
  与统计择一规则继续有效。
- 动作热量优先使用 Effort 实际时长；次数训练无实际时长时才使用明确标为估算的回退。
- 体重只取 Session 开始时间之前最近的有效 BodyEntry，不从 UserProfile 回退。
- Session 热量求和来源动作记录，不能再按 elapsed time 重算；缺体重返回 missing requirement，
  热量保持 `nil`，训练继续。

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
| Model | 名称唯一、ID/关系、独立组、Set/Effort 真值、一对一投影、级联删除 |
| Tool | ID/name、nested set schema、严格 union、旧 schema 恢复、跨空间、幂等、当前计划更新 |
| Migration | 当前 schema 无 plan 打开、启动门禁展开旧聚合处方/Effort、projection key 预修复、旧快照/备份、休息归属、统计不重复、双空间 marker |
| Candidate | 本地搜索、最近值、nil、只修改草稿 |
| Catalog/Image | 空库静默、按动作激活、fill-only、资源加载、显式生成、上传、删除、合并与备份 |
| Coordinator | laterality 顺序、duration/休息自动推进、revision 去重、暂停恢复、跳过替换、自动收口 |
| Camera | attempt 单终态、成功 key、幂等 stop、单 Alert、权限、目标 Effort、中断、重录、磁盘、热压力 |
| Privacy | 远程选择、无麦克风、备份、恢复、清除 |
| UI | 一步开始、嵌套进度、常驻录像、分享预览、缺体重、VoiceOver、Dynamic Type、长概览/名称、空态 |
