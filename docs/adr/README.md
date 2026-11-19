# Soma 架构决策

先读压缩起点，再按顺序阅读最近三个营销版本。版本以 `project.yml` 和 [CHANGELOG](../../CHANGELOG.md) 为准。

| 版本 | 文档 | 范围 |
| --- | --- | --- |
| ≤0.0.35 | [压缩起点](0000-origin-through-0.0.11.md) | 仍然有效的架构决策 |
| 0.0.36 | [ADR 0151](0151-training-energy-in-total.md) | 总消耗直接加入训练列表估算，兼容历史能量依据 |
| 0.0.37 | [ADR 0152](0152-coach-progress-reliability.md)、[ADR 0153](0153-agent-daily-energy-read.md) | 教练连续性、进展原位刷新与模型读取当日日账 |
| 0.0.38 | [ADR 0154](0154-exercise-muscle-map-ids.md) | 新建动作保存受力块 ID |

每次发布，把滑出窗口的原文移入[文档归档](../archive/README.md)，将仍有效的边界合并进压缩起点。
窗口内最早文档的前驱指向起点。同一修订的正向与反向关系写入两份文档的头部，并由 `make check` 验证。
默认只阅读活文档。产品不变量见[工程契约](../../CLAUDE.md)，验证证据见[验收清单](../acceptance.md)。
新增文档使用[模板](template.md)。

- [ADR 0152 · 教练连续性与进展刷新](0152-coach-progress-reliability.md)，下游见[验收矩阵](../acceptance.md)、[ReAct 协议](../react-agent.md)和[视频能力回归 BUG 0071](../bugs/0071-unverified-video-input.md)。
- [ADR 0153 · Agent 读取当日日账](0153-agent-daily-energy-read.md)，下游见 [Agent Tool 目录](../engineering/agent-tool-catalog.md)。
