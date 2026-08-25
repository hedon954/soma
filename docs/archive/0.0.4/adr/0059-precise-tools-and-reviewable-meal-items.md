# ADR 0059：精确 Tool 查询、通用记录 CRUD 与可审查食物项

- 状态：已采纳
- 日期：2026-08-11
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0004](../../0.0.1/adr/0004-progressive-skills-fixed-tool-contract.md) 中每个记录动作使用独立固定 Tool 名称的边界
  - [ADR 0028](../../0.0.1/adr/0028-semantic-exercise-identity.md) 中每次语义归一必须返回完整动作列表的边界；稳定动作 ID 保持不变
  - [ADR 0050](../../0.0.3/adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md) 中 core 暴露十一个 Tool 的边界
- 后续替代：
  - [ADR 0064](../../0.0.5/adr/0064-deterministic-quick-write-and-latest-inline-review.md) 将 record reference 扩展为最新回复原位 CRUD 与修订上下文
  - [ADR 0065](../../0.0.5/adr/0065-intent-scoped-tools-and-prefix-stable-prompts.md) 将 `mutate_user_data` 从常驻 core 移入按写意图暴露的 records 组
  - [ADR 0069](../../0.0.6/adr/0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) 用按领域单一职责 Tool 替代通用查询与通用 CRUD
- 后续修订：
  - [ADR 0084](../../0.0.7/adr/0084-inline-meal-breakdown-and-derived-totals.md) 把食物项从只读审查改为聊天内可编辑
    事实来源，汇总变为纯派生；精确 Tool 查询与 `MealItem` 结构继续有效
- 上游依据：
  - [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
  - [BUG 0011](../../../bugs/0011-meal-correction-misattributed-media.md)

## 背景

读取 Tool 大量重叠且能全量返回动作/计划；训练、饮食、身体各自复制 create/update Tool；结果是
长字符串，UI 只能显示通用过程卡。饮食营养使用非空标量，缺失值被表现为 0，也没有食物项可审查。

## 决策

1. `query_user_data` v2 提供精确 ID、搜索、日期、排序、cursor、默认 3/最大 10、summary/detail
   与字段投影；所有参数必须实际生效，detail 要求精确 ID。
2. `mutate_user_data` 用 operation、record type、record ID 和类型 payload 统一训练/饮食/身体 CRUD；
   运行时严格校验，删除继续要求当前消息明确授权。
3. Tool result 使用 `{ok, code, message, data?, record_refs?, page?}`。新模型只暴露 13 个 Tool；
   v1 名称和 schema 作为隐藏兼容路径保留。
4. 远程 Job 显式携带 Tool schema version，并与本地共享分组暴露策略，不再发送全部工具。
5. 饮食营养改为 optional；新增有序 `MealItem` 和营养来源。只有完整 item 值才自动汇总，用户
   编辑 aggregate 优先。
6. 聊天由 typed record ref 渲染单张饮食结果卡；过程 Tool 折叠，详情支持 item CRUD 和排序。

## 未选择的方案

- 继续给模型全库名称：动作库增长后成本无界。
- 从 final prose 解析饮食卡：破坏 Tool 是业务事实来源的边界。
- 用 0 代表未知：违反 truth over completeness。

## 结果

### 正向影响

- Tool 前缀更小、查询可控、UI 能直接展示稳定记录，饮食缺失值保持真实。

### 成本与限制

- v1/v2 双协议在历史 Job 与备份兼容期内需同时维护。

## 验证

- Schema、分页、过滤、字段投影、别名、远程版本、饮食迁移/汇总/编辑和数据空间隔离测试。

## 参考

- [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
