# Soma 产品与技术调研

本目录保存尚未成为产品契约的证据、竞品与技术可行性研究。研究稿不直接授权实现；结论被
采纳后，必须转化为 PRD、ADR 或工程协议。

## 索引

| 调研 | 状态 | 下游落地 |
| --- | --- | --- |
| [Apple 本地中文听写](2026-09-05-apple-local-speech.md) | 已转化，真机准确率待对比 | PRD 056、ADR 0119 |
| [动作库、训练计划、带练与视频复盘](2026-07-31-exercise-library-plans-guided-training.md) | 已转化并部分修订 | PRD 010、ADR 0028—0035、训练领域架构；带练体验由后续调研深化 |
| [训练计划编排、沉浸式带练与真实取景](2026-08-03-guided-workout-flow-and-capture.md) | 已转化并部分修订 | PRD 013、ADR 0038、BUG 0006；录像反馈由后续调研深化 |
| [带练录像策略、语音节奏、完成反馈与历史管理](2026-08-04-guided-workout-recording-cues-and-review.md) | 已转化 | PRD 014、ADR 0039、BUG 0010 |
| [持久 Agent Job、事件流与 Live Activities](2026-07-31-durable-agent-jobs-live-activities.md) | 已转化 | PRD 011、ADR 0031—0027、Agent Job 协议 |
| [私人健身教练的情境化主屏组件](2026-08-04-contextual-private-coach-widgets.md) | 已转化 | PRD 017、ADR 0042 |
| [全界面 GUI 精简与渐进披露审计](2026-08-05-ui-simplification-review.md) | 已转化 | PRD 020 |
| [减脂与增肌目标导向进展指标](2026-08-26-goal-directed-progress-metrics.md) | 已转化 | PRD 046、ADR 0103；[历史与图表重设计提议](2026-09-05-progress-history-and-chart-design.md)拟修订时间入口和指标层级 |
| [进展历史与图表逻辑重设计](2026-09-05-progress-history-and-chart-design.md) | 已转化，实施中 | [修订自目标导向研究](2026-08-26-goal-directed-progress-metrics.md)；落地 PRD 053／054 |

## 生命周期规则

- 调研进入正式范围后，调研头部用“下游落地”链接正式文档。
- 正式文档头部用“上游依据”反向链接调研。
- 后续研究推翻旧研究时同样建立“后续修订”与“修订自”的双向关系。
