# Soma 产品需求文档

活 PRD 链与对话压缩相同：先读**压缩起点**，再读最近 3 个营销版本的增量。当前窗口是
`0.0.21`、`0.0.20`、`0.0.19`（以 `project.yml` 的 `MARKETING_VERSION` 与 `CHANGELOG.md`
版本标题为准，不按文件日期）。

产品不变量以 [工程契约](../../CLAUDE.md) 的 Product contract 为准。0.0.18 及更早的**原文**在
[文档归档](../archive/README.md)，仅供人类考古；Agent 默认不要读取归档。

## 活文档窗口规则

阅读顺序：

```text
[PRD 000 压缩起点] → 0.0.19 → 0.0.20 → 0.0.21
```

压缩起点是双向链的起始节点：只保留滑出窗口后**仍然成立的最终要求**，不含沿途被替代的过渡
细节，也不是旧 PRD 文件清单。窗口内最旧活 PRD 的「修订自」指向起点；起点没有更早的活前驱。

每次新 App 发布时**不要只把滑出版本搬进 archive**。必须：

1. `git mv` 滑出版本的原文到 `docs/archive/<version>/`（归档留在 Git，不加入 gitignore）；
2. 把「现有压缩起点 + 该版本仍有效的最终状态」**合并**成新的压缩起点，替换旧起点；
3. 新窗口最旧活 PRD 的修订自指向新起点。

这与 Agent 消息滚动压缩相同：折叠滑出窗口的那一轮，活链始终是「收口 → 最近三版」。

## 当前窗口

| 文档 | 版本 | 角色 |
| --- | --- | --- |
| [000：0.0.18 及更早收口](000-origin-through-0.0.11.md) | ≤0.0.18 | 压缩起点 |
| [051：可自愈工具参数与宽幅进展明细](051-self-healing-tool-arguments-and-wide-progress-disclosure.md) | 0.0.19 | Tool 规则有效；进展浮层由 054 部分替代 |
| [052：教练、训练与生命周期可靠性](052-coach-training-and-lifecycle-reliability.md) | 0.0.19 | 活增量 |
| [053：动态能量估算与可解释的进展展示](053-adaptive-energy-estimation-and-progress.md) | 0.0.19 | 已采纳；ADR 0115 补充默认参考估算 |
| [054：进展历史与四周期统计](054-progress-history-and-periods.md) | 0.0.19 | 已采纳；ADR 0115 恢复指标明细，0116 按四周期区分信息重点 |
| [055：动作分类与餐次明细](055-exercise-facets-and-meal-breakdown.md) | 0.0.21 | 分类轴与明细汇总由 057 部分修订 |
| [056：完整视频、连续听写与分享明细](056-video-speech-and-share-readability.md) | Unreleased | 听写呈现由 057 部分修订 |
| [057：快捷聚焦、实时听写与进展圆环](057-coach-focus-progress-rings-and-library-clarity.md) | Unreleased | 已采纳 |
| [058：反馈失败、时长时分秒与可编辑热量](058-feedback-duration-and-editable-calories.md) | Unreleased | 已采纳 |

## 阅读约定

- 「修订自」是活链前驱，「后续修订」是活链后继。
- “当前要求”表示仍然有效，并应由当前实现持续满足。
- 产品验收证据集中在 [验收清单](../acceptance.md)。
- 技术与交互取舍集中在 [ADR](../adr/README.md)。
- 新 PRD 从 [模板](template.md) 开始。

## 修订关系

- 旧 PRD 用“后续修订”链接所有改变其边界的新 PRD。
- 新 PRD 用“修订自”反向链接每一份被改变的旧 PRD。
- 部分修订只改变明确段落，其余旧要求继续有效；索引阶段必须与文档头部状态一致。
- 双向链接由 `make check` 自动验证活文档互链。归档原文是考古，不要求与活文档互链。
