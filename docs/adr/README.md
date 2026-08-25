# Soma 架构决策记录

本目录只保留**最近 3 个营销版本**窗口内引入的活 ADR。当前窗口是 `0.0.12`、`0.0.11`、
`0.0.10`。更早决策的原文在 [文档归档](../archive/README.md)；默认不要读取归档，除非维护者
明确要求历史。

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

## 活文档窗口规则

每次新 App 发布后，把滑出 3 版本窗口的那个营销版本的原始 ADR（以及同期 PRD）压缩进
`docs/archive/<version>/`。归档留在 Git，不加入 gitignore。活目录 README 只索引窗口内文档。

## 当前窗口

| ADR | 版本 | 状态 | 决策 |
| --- | --- | --- | --- |
| [0091](0091-action-level-planned-rest.md) | 0.0.10 | 已采纳 | 计划组间歇与换侧间歇归动作；开始训练时编译到逻辑组，实际休息证据仍逐组保存 |
| [0092](0092-react-internal-retry-and-user-controlled-recovery.md) | 0.0.11 | 已采纳 | 无可见增量的模型步骤执行三次 1/2/4 秒退避；失败越过 Loop 后只允许用户释放 |
| [0093](0093-bounded-per-reply-multimodal-feedback-context.md) | 0.0.11 | 已采纳，个人使用阶段 | 每条 AI 回复可提交文字、媒体和评分，并附带单 Turn 有界脱敏执行摘要 |
| [0094](0094-user-first-versioned-bundled-action-art.md) | 0.0.11 | 已采纳 | 动作图使用用户图优先、新版内置图次之；专属离线图不少于 239 |
| [0095](0095-metrickit-confirmed-crash-reports.md) | 0.0.11 | 已采纳，个人使用阶段 | 只有 MetricKit 明确崩溃证据可生成报告；启动哨兵只保留上下文 |
| [0096](0096-source-backed-model-multimodal-capabilities.md) | 0.0.11 | 已采纳 | 多模态与直传视频能力必须有明确来源；缺少来源时为未知，禁止按模型名硬编码 |
| [0097](0097-current-baseline-performance-budget-and-cache-invalidation.md) | 0.0.12 | 已采纳，Release 真机量化验收中 | 固定当前安装基线、120 Hz 性能预算、分页/后台聚合与图片媒体缓存失效规则 |
| [0098](0098-user-configurable-react-active-runtime-timeout.md) | 0.0.12 | 已采纳，待真机界面验收 | ReAct 自动 3/5/10 分钟或自定义 3–60 分钟活动执行预算，与步骤上限同区配置 |
| [0099](0099-behavior-preserving-modernization-and-three-version-docs.md) | 0.0.12（Unreleased） | 已采纳 | 行为保持的代码拆分与死代码删除；活 PRD/ADR 只保留最近 3 个营销版本 |

新决策使用 [ADR 模板](template.md)。

状态定义：

- **已采纳**：当前实现和后续开发都应遵守；
- **部分已替代**：部分决策由后续 ADR 修订，其余部分仍生效；
- **已替代**：由后续 ADR 明确取代；
- **已废弃**：不再适用，但保留历史原因。

## 替代关系

- 旧 ADR 用“后续替代”链接新 ADR；新 ADR 用“替代”或“部分替代”反向链接旧 ADR。
- 一个决策只被部分替代时，旧文继续保存仍有效内容和替代范围，不能直接改写成仿佛旧决策
  从未存在。
- 研究转 ADR 时使用“下游落地”与“上游依据”形成双向关系。
- 双向链接由 `make check` 自动验证；新增决策从 [ADR 模板](template.md) 开始。
- 生命周期门禁仍扫描归档原文。
