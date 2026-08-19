# ADR 0071：整型业务身份与明确领域关系

- 状态：部分已替代；Int64 业务身份、动作关系和启动门禁继续有效，历史 VersionedSchema 打开路径由 ADR 0075 替代
- 日期：2026-08-15
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0028](0028-semantic-exercise-identity.md) 中动作和关联记录使用 UUID 的表示方式
  - [ADR 0029](0029-versioned-training-plans-and-session-facts.md) 中训练领域使用 UUID 软引用的表示方式
- 后续替代：[ADR 0075](0075-current-swiftdata-schema-without-historical-versions.md) 取消历史 VersionedSchema 链；本 ADR 的 Int64、动作关系和启动门禁继续有效
- 后续修订：[ADR 0078](0078-batch-create-exercise-and-workout.md) 将创建动作/训练改为批量数组，新建记录 ID 仍由本机分配、模型不得指定
- 上游依据：[PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md)
- 下游落地：
  - [ADR 0073](0073-independent-set-prescriptions-efforts-and-guided-finalization.md) 将 Int64 与明确关系合同扩展到独立组、Effort 和投影关系
  - [训练领域模型与运行时协议](../engineering/training-domain-model.md)

## 背景

模型需要复制长 UUID，训练记录仍允许 `exerciseID=nil`，数据库关系又只靠 Store 规则维护。动作
身份虽然稳定，但“无动作库记录不能创建”的领域约束没有进入模型层和持久层共同边界。

## 决策

1. Tool 可寻址的本机身体业务实体使用每实体、每数据空间从 1 开始单调递增的 `Int64` 身份。
2. Conversation Session、Turn、Agent Job/Trace/Event、媒体引用、远程协议和外部 Provider ID
   继续使用 UUID 或字符串；这些身份不暴露为业务 Tool 参数。
3. App 使用持久化序列分配器和唯一约束，不依赖底层 SQLite 未公开自增实现。
4. `WorkoutEntry`、`TemplateExercise`、`ExercisePerformance` 必须拥有存在的动作关系。新记录、导入
   和带练投影都先解析或创建动作，再保存引用。
5. 动作被引用时不能直接删除；归档保留引用，合并先事务重绑。旧空动作使用明确的待确认占位，
   不伪造具体动作。
6. 业务 ID、关系、编码快照和备份映射由启动门禁回填；新导出使用整型业务 ID，旧 UUID 备份继续
   可恢复。历史 VersionedSchema 打开路径由 ADR 0075 替代，当前只打开 `SomaDataSchema`。
7. App 根生命周期维护迁移门禁。检测到旧 schema 时，个人空间与演示空间依次迁移、校验并写入
   独立 marker；全部完成前不创建业务 Root、不启动 Agent Job runner、不允许任何业务写入。
   迁移失败时保留旧 store，展示可重试错误和脱敏诊断，不允许静默进入半迁移状态。

## 未选择的方案

- 不只增加模型侧短句柄并永久保留 UUID 作为业务事实。
- 不把聊天和 Agent 基础设施改成整型；它们需要跨设备/服务的幂等身份。

## 结果

### 正向影响

- Tool 参数更短，关系完整性成为持久模型约束，动作改名不切断历史。

### 成本与限制

- 数据模型、归档 DTO、种子数据、导入去重和所有 Store 查询都需要迁移。

## 验证

- 启动迁移门禁、失败重试与幂等 marker、关系删除规则、动作合并、HealthKit 导入、备份恢复和
  双空间隔离测试。

## 参考

- [数据库结构](../engineering/database-schema.md)
- [训练领域模型](../engineering/training-domain-model.md)
