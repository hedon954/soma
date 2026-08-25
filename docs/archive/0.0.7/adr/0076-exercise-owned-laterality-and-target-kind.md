# ADR 0076：侧别与完成方式归动作定义，组只保存必要参数

- 状态：已采纳
- 日期：2026-08-17
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0073](0073-independent-set-prescriptions-efforts-and-guided-finalization.md) 中把 `laterality` 当作计划动作可选项、把 `targetKind` 当作每组独立变量并向用户展开的产品边界
- 后续替代：[ADR 0091](../../../adr/0091-action-level-planned-rest.md) 将两类计划间歇与侧别并列为动作级配置；侧别与完成方式归动作定义的边界继续有效
- 上游依据：
  - [PRD 031](../prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
  - [PRD 020](../../0.0.3/prd/020-gui-simplification-and-progressive-disclosure.md)
  - [PRD 010](../../0.0.1/prd/010-exercise-library-plans-guided-training.md)
- 下游落地：
  - [训练领域模型与运行时协议](../../../engineering/training-domain-model.md)
  - [数据库结构与 ER 图](../../../engineering/database-schema.md)

## 背景

独立逻辑组和 Effort 分层仍然正确：左右分开时一次“组”需要两条执行证据，带练也必须按侧推进。
但把侧别、完成方式、组类型、逻辑组序号和实际用时摊到每一组，会让训练记录和处方编辑变成内部
模型说明书。用户要改的是“这个动作怎么做”，不是“这一组属于哪个逻辑组”。

侧平板支撑这类按时长、常分左右的动作，如果每组再选一次按次数/按时长和侧别，记录页会同时出现
次数、时长、重量、逻辑组和空的间歇，无法日常使用。

## 决策

1. `ExerciseDefinition` 保存动作级 `laterality` 与 `targetKind`。空字符串表示尚未配置，展示时
   分别按全身（`.none`）和按次数解释，不能用动作名称猜测。
2. 侧别只允许：全身（`.none`）、左右分开（`.both`）、只左边、只右边。完成方式只允许按次数或
   按时长。这两项在动作详情和计划动作编辑器各出现一次，写入动作本身；计划组和训练记录不再
   提供第二套选择器。
3. 每一组只编辑动作定义下有意义的参数：按次数则次数与重量，按时长则秒数与重量；左右分开时
   才出现左右重量或左右证据。组类型、组间歇和备注仍可在计划里填写，但不进入训练记录首屏。
4. `TemplateExercise.laterality` 和每组 `targetKind` 继续作为带练编译与历史快照字段，从动作定义
   复制，不作为用户可并列修改的第二事实。新 Session 优先读取动作定义；定义未配置时才回退计划
   快照，并在空值上回填动作。
5. `WorkoutSetEvidence` 仍可保存 logical set index、side、kind 与 target kind，供投影和 `.both`
   左右配对。界面不展示“逻辑组”“执行证据”；保存时按顺序补齐空的组序号，不把未展示的已有值
   抹成常见值。
6. 启动时幂等回填：内置目录只填充空的动作侧别/完成方式；计划或记录里出现的 `.both/.left/.right`
   或 duration 证据可以写入仍为空的动作字段。禁止从名称推断，也禁止把默认 `.none`/repetitions
   当成用户已配置而覆盖目录。

本决策不删除 Effort、不改变 missing-is-nil，也不恢复 VersionedSchema。追加的动作列按 ADR 0075
由系统轻量推断；不兼容删列以后再单独立项。

## 未选择的方案

- 只在记录页折叠字段、动作和计划仍各自保存侧别与完成方式：用户会在三处看到不同答案。
- 按动作名称猜测侧平板为 duration/both：违反 truth over completeness。
- 立刻删除 `WorkoutSetEvidence` 与处方上的冗余列：会破坏已投影记录和进行中 Session。

## 结果

### 正向影响

- 训练记录每组默认只出现次数或时长，外加重量。
- 侧别和完成方式改一次，计划和以后的记录都跟着用。

### 成本与限制

- 已开始的 Session 仍使用当时快照；改动作定义影响之后新开的训练。
- 旧记录若从未配置动作完成方式，需目录回填、计划证据或用户在动作详情点一次。

## 验证

- 单元测试覆盖空值回填、目录 fill-only、记录编辑器按动作选择主字段。
- `make check` 与 `make verify`。
- 真机打开进展中的侧平板支撑记录，确认不再出现逻辑组、组类型和完成方式分段器。

## 参考

- [ADR 0073](0073-independent-set-prescriptions-efforts-and-guided-finalization.md)
- [PRD 031](../prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
