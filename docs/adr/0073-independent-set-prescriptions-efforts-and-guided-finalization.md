# ADR 0073：独立逐组处方、原子执行与确定性带练收口

- 状态：部分已替代；独立处方、Effort 归属与自动收口继续有效，完整相机 activation 由 ADR 0074 细化，历史 VersionedSchema 链由 ADR 0075 替代，侧别与完成方式由 ADR 0076 归动作定义，业务版本链与热量算法版本字段由 ADR 0090 删除
- 日期：2026-08-16
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0029](0029-versioned-training-plans-and-session-facts.md) 中 `TemplateExercise` 保存动作级统一目标、`WorkoutSet` 同时承载左右实际证据的表示方式
  - [ADR 0039](0039-event-driven-guided-recording-cues-and-review.md) 中录像直接归属 `WorkoutSet`、Session Review 等待用户确认才完成的边界
  - [ADR 0060](0060-guided-performance-workout-entry-projection.md) 中仅以可空来源 UUID 做应用层去重、投影只复制次数与重量的边界
- 上游依据：
  - [PRD 031](../prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
  - [ADR 0071](0071-integer-business-identities-and-explicit-relations.md)
  - [BUG 0019](../bugs/0019-guided-recording-attempt-terminal-and-duplicate-alerts.md)
- 后续替代：
  - [ADR 0090](0090-current-state-business-models-and-session-facts.md) 删除版本化模板关系与热量算法版本字段，保留独立组、Session 快照和状态机 transition revision
  - [ADR 0074](0074-bounded-guided-camera-activation-and-partial-evidence.md) 细化录像 attempt 的起点、准备阶段 deadline、camera-ready preflight、部分文件语义和系统中断恢复；本 ADR 的 Effort 归属与单终态原则继续有效
  - [ADR 0075](0075-current-swiftdata-schema-without-historical-versions.md) 取消冻结 V3/V4/V5 与跨级磁盘夹具；独立组、Effort、projection key 与启动数据回填继续有效
  - [ADR 0076](0076-exercise-owned-laterality-and-target-kind.md) 将用户面对的 laterality 与 targetKind 改为动作定义，计划组和记录不再并列编辑这两项；独立组与 Effort 编译规则继续有效
- 下游落地：
  - [训练领域模型与运行时协议](../engineering/training-domain-model.md)
  - [数据库结构与 ER 图](../engineering/database-schema.md)
  - [BUG 0021](../bugs/0021-unique-optional-projection-key-blocks-launch-migration.md)

## 背景

动作级 `targetSets/targetReps/targetWeight/targetRest` 能快速表达统一处方，却无法保存用户明确要求的
逐组差异、时长目标或左右两侧不同重量。继续把 `.both` 压在一条 `WorkoutSet` 上，也无法让左右
各自拥有实际值、状态和视频。若简单把左右拆成两个 Set，又会把用户理解的一组显示成两组，破坏
组进度、热身/工作组语义和“每动作首个工作组”录像策略。

与此同时，现有录像服务使用一次 async start/stop 调用表示活动，Delegate 可以在 Coordinator
不知情时提前结束；完成组时再次 stop 会产生第二个失败。最后一组虽然已逐步保存事实，仍要用户
点击完成按钮才能把 Session 收口。

## 决策

### 1. 计划处方以独立逻辑组为事实

1. `TrainingProgram` 保存计划级 `overview`；旧 `goal` 只作为迁移兼容来源。
2. `TemplateExercise` 保存动作身份、顺序、动作级 `laterality`、器械和备注，不再以动作级聚合
   字段作为新处方事实。
3. `TemplateSetPrescription` 是版本化模板下的独立逻辑组。每条保存：
   - 单调顺序；
   - `warmup/working`；
   - `repetitions/duration`；
   - 对应的次数或秒数；
   - 按 laterality 有效的重量；
   - 左右间歇、组后间歇和可选备注。
4. target kind 是严格 union。未提供目标继续为 `nil`，不能以编辑器默认值补齐。
5. 复制上一组只复制当前值并生成新实体，之后两组不共享默认或联动更新。

### 2. 逻辑组与原子执行分层

1. `WorkoutSet` 表示用户看到的逻辑组，保存组类型、目标类型、组后间歇、顺序和逻辑状态。
2. `WorkoutEffort` 表示实际执行原子，保存 `none/left/right`、计划与实际次数/秒数、重量、时间戳、
   状态和录像引用。
3. laterality 编译规则固定：
   - `.none` → `[none]`；
   - `.left` → `[left]`；
   - `.right` → `[right]`；
   - `.both` → `[left, right]`，固定先左后右。
4. `.both` 的 left/right 属于同一 Set，组数和训练效果只计算一次；容量、录像和完成证据按 Effort
   计算。
5. 左侧完成、右侧未完成是合法的部分证据，不能被改写成整个逻辑组已完整完成。

### 3. 版本、关系与迁移

1. 历史 `SomaDataSchemaV3/V4/V5` 冻结链与跨级磁盘夹具由 [ADR 0075](0075-current-swiftdata-schema-without-historical-versions.md)
   替代。当前只打开 `SomaDataSchema`，不带 `migrationPlan`。
2. 模板版本、计划动作、独立组以及 Session、Performance、Set、Effort 建立可遍历关系；受
   SwiftData 迁移限制保留的 UUID 锚点不再是 Tool 或 UI 的业务身份。
3. Tool 可寻址实体继续遵循 ADR 0071 的 Int64 分配与动作关系合同。迁移先修复 nil/重复业务 ID，
   再收紧新写入校验。
4. `ExercisePerformance` 与投影 `WorkoutEntry` 建立显式一对一关系，并增加稳定 projection key。
   带练投影使用 `guided-performance:<uuid>`，非投影记录使用 `entry:<uuid>`。unique 索引保留，
   因此启动迁移即使 marker 已完成也必须先把空 key 补成互不重复的值，不能再从模型上撤掉
   unique。来源 UUID 继续作为旧备份与审计锚点，不单独承担唯一性。
5. Store 统一执行跨模型级联、媒体回收和动作 deny/归档规则；SwiftData 可选关系不能被解释为业务
   可空。
6. 个人空间和演示空间分别执行迁移、校验与 marker。任一失败时保留全部旧业务事实、不挂载业务
   Root，并允许从已经完成的 schema stage 幂等重试；不要求把物理文件回滚到旧 checksum。
   打开路径不再用跨级磁盘夹具自证，见 ADR 0075。

### 4. V4→V5 映射保持真值

1. `goal` 原样成为 `overview`。
2. 每条旧 `TemplateExercise.targetSets=N` 展开为 N 条独立处方；首组热身标记只影响第一条。
3. 旧模型没有可靠左右证据，全部迁移为 `.none`；禁止按动作名称、器械或常识猜侧别。
4. 旧模型只表达次数，迁移为 repetitions；缺失次数继续为 `nil`。
5. 旧运行时把休息附着在下一组时，迁移将已知 planned/actual rest 左移到其所属前一逻辑组；无法
   证明归属时保持为空。
6. 旧 Session/Performance Data 快照使用显式 legacy decoder；任何无法解码的业务快照使该空间
   迁移失败，禁止静默生成空计划。
7. schema 1–4 备份继续可读；无法证明安全的旧 record reference 显式失效，不得碰巧指向重编号
   后的其他实体。

### 5. 带练转换由持久 deadline 与 revision 驱动

1. Session 保存当前 Performance、Set、Effort、阶段 deadline 与 transition revision。
2. 次数 Effort 由用户确认完成；时长 Effort 到期自动提交实际时长。
3. `.both` 左侧结束后进入左右间歇，右侧结束后进入组后间歇；休息归零自动进入三秒倒计时。
4. 新动作仍要求用户确认“准备本动作”，不自动跨器械开组。
5. 暂停冻结 deadline；恢复、View 重建、重复 tick、前后台和重启都以 revision 做 compare-and-set，
   同一转换只能提交一次。

### 6. 录像使用 attempt 终态，而不是 View 推断

1. 每次自动或手动请求建立唯一 attempt，绑定一个目标 Effort。
2. attempt 只允许一次终态：`saved`、`failed` 或 `cancelled`。
3. Camera adapter 把 Delegate 的 start/finish、系统中断、后台和 stop 归一为 attempt 事件；Coordinator
   消费终态并成为唯一用户 Alert 投影源。
4. `AVErrorRecordingSuccessfullyFinishedKey == true` 且文件有效时按成功处理，即使 Delegate 同时
   提供非空 error。
5. 已终结 attempt 的 stop 是幂等消费，不产生 `stop-missing` 或第二个警告。
6. 自动 attempt 失败后暂停自动策略但不停止训练；用户手动重试建立新 attempt。

### 7. 动作记录先于 Session 自动完成

1. Performance 的全部 Effort 终态且至少一个完成时，物化唯一 `WorkoutEntry`；全跳过不创建记录。
2. 投影保存实际 Effort 证据并保留 `nil`，不以计划目标补实际值。
3. 最后一个 Effort 的收口顺序是：最后一条动作记录 → 全部 Performance 终态 → Session completed/
   finalized → 系统训练投影结束 → 本地分享预览。
4. `WorkoutSession` 继续表达计划执行；不新增同义 `PlanExecution`。
5. 分享页只读取已经完成的本地事实；系统分享仍需用户明确点击。

### 8. 热量按动作记录聚合

1. 每条动作记录使用本地 MET 规则：优先 Effort 实际时长，次数训练缺时长时才使用带估算标记的
   回退。
2. 参考体重取 Session 开始时间之前最近的有效身体记录，再回退用户资料参考体重。
3. Session 热量只求和来源动作记录，不能同时用 Session elapsed time 重算。
4. 缺体重时热量为 `nil` 并返回结构化缺失要求；不写 `0`、不阻断训练、不自动回填旧历史。
5. 持久化 MET、计算时长、估算标记和算法版本，估算时长不成为实际训练时长。

## Tool 与兼容边界

- 新计划 Tool 用嵌套逐组结构递归校验，不继续暴露 `target_sets + target_reps` 聚合写入。
- 新调用只暴露新 schema；已持久化旧 Job/Checkpoint 仍可由版本化 decoder 转换，不能在升级时
  丢失用户已授权工作。
- Server 只校验并转发设备生成的协议，不保存训练计划或身体业务数据。
- 本地 GUI 与 Tool 共用同一个处方验证器和版本创建 Store。

## 未选择的方案

- 动作级默认处方加少量例外：用户明确要求各组完全独立，且默认传播容易改写历史意图。
- `.both` 直接算两个 Set：会让用户看到的组数、进度和首工作组策略翻倍。
- 在一个 Set 上增加 left/right 两套所有实际字段：状态、录像、时间戳和未来恢复逻辑会继续膨胀。
- View 倒计时归零直接推进：View 重建、前后台和重启无法保证只执行一次。
- 录像只靠 Camera state 或 Alert 文本去重：无法识别同一 attempt，也无法清理提前结束后的陈旧状态。
- Session 完成后再批量生成动作记录：中途失败会让计划执行存在而动作历史缺失。
- 缺体重时写 `0 kcal` 或使用常见体重：违反 truth over completeness。

## 结果

### 正向影响

- 计划可以忠实表达左右、时长和任意逐组差异，执行、进度和录像仍符合用户理解的一组。
- deadline/revision 与 attempt 终态让自动推进和相机失败可恢复、可去重。
- 动作记录、计划执行、热量与分享拥有明确的事实顺序。
- 旧聚合处方、旧备份和在途 Agent Job 有显式启动回填路径。

### 成本与限制

- SwiftData 增加模型、关系、迁移和备份 DTO，执行状态机从 Set 细化到 Effort。
- 旧计划只能迁移为 `.none + repetitions`，因为不存在可证明的左右与时长事实。
- 真实相机 Delegate、系统中断、语音和分享仍必须在维护者设备验收；模拟器和单元测试不能替代。

## 验证

- 启动门禁在当前 schema 上幂等展开旧聚合处方、补齐 projection key，并覆盖失败重试、marker
  与旧快照/备份测试。
- laterality 编译、target kind union、逐组独立复制、左右不同重量和 nil 保留测试。
- deadline/revision 在暂停、View 重建、重复 tick、前后台与重启下只推进一次。
- attempt 提前成功/失败、成功 key、重复 Delegate、幂等 stop、同 attempt 单 Alert、新 retry 新 Alert。
- 投影 business ID、动作关系、一对一 projection key、suppression、级联与统计去重。
- 最后一个 Effort 按动作记录、Session、系统投影、分享顺序收口一次。
- 热量日期体重、缺体重、部分 Effort、休息与 Session 求和测试。
- `make check`、`make verify` 以及维护者真机清单；未完成的真机项目必须明确保留待验收状态。
