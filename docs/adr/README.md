# Soma 架构决策记录

活 ADR 链与对话压缩相同：先读**压缩起点**，再读最近 3 个营销版本的增量。当前窗口是
`0.0.21`、`0.0.20`、`0.0.19`。0.0.18 及更早的**原文**在 [文档归档](../archive/README.md)，
仅供人类考古；Agent 默认不要读取归档。

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

## 活文档窗口规则

阅读顺序：

```text
[ADR 0000 压缩起点] → 0.0.19 → 0.0.20 → 0.0.21
```

压缩起点是双向链的起始节点：只保留滑出窗口后仍然成立的最终决策。窗口内最旧活 ADR 的
「部分替代」指向起点；起点没有更早的活前驱。

每次新 App 发布时**不要只把滑出版本搬进 archive**。必须把原文移入
`docs/archive/<version>/`，并把「现有压缩起点 + 该版本仍有效的最终决策」合并成新起点。
归档留在 Git，不加入 gitignore。

## 当前窗口

| ADR | 版本 | 状态 | 决策 |
| --- | --- | --- | --- |
| [0000](0000-origin-through-0.0.11.md) | ≤0.0.18 | 压缩起点 | 0.0.18 收口后仍约束实现的架构决策 |
| [0109](0109-schema-guided-tool-argument-recovery.md) | 0.0.19 | 部分替代 | Schema 驱动数字归一化与错误回路仍有效；进展浮层由 [0114](0114-progress-periods-and-adaptive-energy.md) 修订 |
| [0110](0110-workout-tool-and-calorie-evidence.md) | 0.0.19 | 已采纳 | 训练 Tool v4 与普通/带练热量共用逐组证据 |
| [0111](0111-agent-response-identity-and-manual-recovery.md) | 0.0.19 | 已采纳 | 入队预建响应，等待、失败与人工重试复用同一消息 |
| [0112](0112-coach-scroll-and-session-behavior.md) | 0.0.19 | 已采纳 | 教练尾随滚动、双击回尾与 Session 日期命名 |
| [0113](0113-capture-and-foreground-lifecycle.md) | 0.0.19 | 已采纳 | 根层快捷相机状态机、首帧后前台恢复与稳定 SwiftData ID |
| [0114](0114-progress-periods-and-adaptive-energy.md) | 0.0.19 | 部分已替代 | 动态校准仍有效；0115 修订默认参考与披露，0116 区分周期信息重点 |
| [0115](0115-energy-default-reference-and-compact-details.md) | 0.0.19 | 部分已替代 | 默认估算与浮层仍有效；日页宏量呈现由 [0122](0122-nutrition-rings-and-period-deficit.md) 修订 |
| [0116](0116-progress-period-specific-focus.md) | 0.0.19 | 已采纳 | 日、周、月、年训练与身体信息重点 |
| [0117](0117-workout-share-editorial-poster.md) | 0.0.21 | 已采纳 | 部分替代 [0000](0000-origin-through-0.0.11.md) 的分享导出外观：固定白底、橙黄色主视觉与连续逻辑组压缩 |
| [0118](0118-exercise-facets-and-meal-colors.md) | 0.0.21 | 部分已替代 | 部位映射与餐次配色仍有效；分类轴由 [0123](0123-exercise-movement-kinds.md) 修订 |
| [0119](0119-full-video-and-append-only-dictation.md) | Unreleased | 部分已替代 | 完整视频与追加-only 草稿仍有效；听写预览由 [0121](0121-live-dictation-preview.md) 修订 |
| [0120](0120-focused-shortcut-prompt.md) | Unreleased | 已采纳 | 选中快捷按钮后省略 Skill 目录并收窄上下文 |
| [0121](0121-live-dictation-preview.md) | Unreleased | 已采纳 | 未确认听写片段只作输入框预览，确认后才写入草稿 |
| [0122](0122-nutrition-rings-and-period-deficit.md) | Unreleased | 已采纳 | 日页营养圆环与推荐摄入；周月年不展示环或周期跳转 |
| [0123](0123-exercise-movement-kinds.md) | Unreleased | 已采纳 | 动作库去掉受力肌群轴，模式映射为封闭动作类型 |
| [0124](0124-smtp-feedback-failure-taxonomy.md) | Unreleased | 已采纳 | 反馈 SMTP 失败分类与 IPv4 优先 |

新决策使用 [ADR 模板](template.md)。

状态定义：

- **压缩起点**：滑出窗口内容的滚动收口，仍约束实现；
- **已采纳**：当前实现和后续开发都应遵守；
- **部分已替代**：部分决策由后续 ADR 修订，其余部分仍生效；
- **已替代**：由后续 ADR 明确取代；
- **已废弃**：不再适用，但保留历史原因。

## 替代关系

- 旧 ADR 用“后续替代”链接新 ADR；新 ADR 用“替代”或“部分替代”反向链接旧 ADR。
- 「部分替代 / 后续替代」同时作为活链的前驱 / 后继。
- 一个决策只被部分替代时，旧文继续保存仍有效内容和替代范围，不能直接改写成仿佛旧决策
  从未存在。压缩起点折叠的是已滑出窗口的原文，不是把仍有效决策写成从未存在。
- 双向链接由 `make check` 自动验证活文档互链。归档原文不要求与活文档互链。
