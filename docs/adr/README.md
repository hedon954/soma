# Soma 架构决策记录

活 ADR 链与对话压缩相同：先读**压缩起点**，再读最近 3 个营销版本的增量。当前窗口是
`0.0.23`、`0.0.22`、`0.0.21`。0.0.20 及更早的**原文**在 [文档归档](../archive/README.md)，
仅供人类考古；Agent 默认不要读取归档。

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

## 活文档窗口规则

阅读顺序：

```text
[ADR 0000 压缩起点] → 0.0.21 → 0.0.22 → 0.0.23
```

压缩起点是双向链的起始节点：只保留滑出窗口后仍然成立的最终决策。窗口内最旧活 ADR 的
「部分替代」指向起点；起点没有更早的活前驱。

每次新 App 发布时**不要只把滑出版本搬进 archive**。必须把原文移入
`docs/archive/<version>/`，并把「现有压缩起点 + 该版本仍有效的最终决策」合并成新起点。
归档留在 Git，不加入 gitignore。

## 当前窗口

| ADR | 版本 | 状态 | 决策 |
| --- | --- | --- | --- |
| [0000](0000-origin-through-0.0.11.md) | ≤0.0.20 | 压缩起点 | 0.0.20 收口后仍约束实现的架构决策 |
| [0117](0117-workout-share-editorial-poster.md) | 0.0.21 | 部分已替代 | 白底橙黄主视觉仍有效；画布由 [0126](0126-workout-share-pro-max-canvas.md) / [0130](0130-workout-share-fill-or-grow.md) 定为 Pro Max 纸面并按内容铺满或加高 |
| [0118](0118-exercise-facets-and-meal-colors.md) | 0.0.21 | 部分已替代 | 部位映射与餐次配色仍有效；分类轴由 [0123](0123-exercise-movement-kinds.md) 修订 |
| [0119](0119-full-video-and-append-only-dictation.md) | 0.0.22 | 部分已替代 | 原件保留与草稿保护仍有效；听写由 [0121](0121-live-dictation-preview.md)、明确视频拒绝由 [0131](0131-explicit-video-rejection-frame-fallback.md) 修订 |
| [0120](0120-focused-shortcut-prompt.md) | 0.0.22 | 已采纳 | 选中快捷按钮后省略 Skill 目录并收窄上下文 |
| [0121](0121-live-dictation-preview.md) | 0.0.22 | 已采纳 | 未确认听写片段只作输入框预览，确认后才写入草稿 |
| [0122](0122-nutrition-rings-and-period-deficit.md) | 0.0.22 | 部分已替代 | 日页圆环仍有效；估算由 [0129](0129-daily-energy-net-training-increment.md) 加入训练净增量，总缺口由 [0133](0133-paired-day-total-energy-deficit.md) 新增 |
| [0123](0123-exercise-movement-kinds.md) | 0.0.22 | 已采纳 | 动作库去掉受力肌群轴，模式映射为封闭动作类型 |
| [0124](0124-smtp-feedback-failure-taxonomy.md) | 0.0.22 | 已采纳 | 反馈 SMTP 失败分类与 IPv4 优先 |
| [0125](0125-eager-loaded-coach-messages.md) | 0.0.22 | 已采纳 | 已加载聊天页即时排版并常驻缓存；切 Tab／Session 不重画，分页按 30 条 |
| [0126](0126-workout-share-pro-max-canvas.md) | 0.0.23 | 部分已替代 | Pro Max 440×956 基准纸面仍有效；铺满与加高由 [0130](0130-workout-share-fill-or-grow.md) 修订 |
| [0127](0127-agent-workout-weight-and-rest-zero.md) | 0.0.23 | 已采纳 | Agent 训练重量与组间间歇未说明时写 0；0kg 为自重 |
| [0128](0128-remove-healthkit-until-redesign.md) | 0.0.23 | 部分已替代 | 当前不接入 HealthKit；日总计公式由 [0129](0129-daily-energy-net-training-increment.md) 修订 |
| [0129](0129-daily-energy-net-training-increment.md) | 0.0.23 | 已采纳 | 日总计 = Mifflin × 日常系数 + 去重后的训练增量 |
| [0130](0130-workout-share-fill-or-grow.md) | 0.0.23 | 已采纳 | 分享海报能放进 Pro Max 纸面时铺满，超出才加高 |

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

## 0.0.23 新增决策

| 文档 | 状态 | 决策 |
| --- | --- | --- |
| [0131](0131-explicit-video-rejection-frame-fallback.md) | 已采纳，已实现 | 部分替代 ADR 0119：明确视频拒绝后单次有界画面回退 |
| [0132](0132-actionable-error-presentation.md) | 已采纳，已实现 | 用户错误与机器诊断分离，修订 BUG 0025 的技术标识呈现 |
| [0133](0133-paired-day-total-energy-deficit.md) | 已采纳，已实现 | 同日配对累计缺口，日页与仍可摄入合为底部提示 |
