# Soma 产品需求文档

本目录只保留**最近 3 个营销版本**窗口内引入的活 PRD。当前窗口是 `0.0.12`、`0.0.11`、
`0.0.10`（以 `project.yml` 的 `MARKETING_VERSION` 与 `CHANGELOG.md` 版本标题为准，
不按文件日期排序）。

产品不变量以 [工程契约](../../CLAUDE.md) 的 Product contract 为准。更早版本的原始 PRD
已压缩到 [文档归档](../archive/README.md)；默认不要读取归档，除非维护者明确要求历史。

## 活文档窗口规则

每次新 App 发布后，把滑出 3 版本窗口的那个营销版本的原始 PRD（以及同期 ADR）压缩进
`docs/archive/<version>/`：保留按版本归纳的要求与决策摘要，并 `git mv` 原文。归档必须
留在 Git，**不得**加入 `.gitignore`。活目录 README 只索引窗口内文档。

## 当前窗口

| 文档 | 版本 | 核心变化 |
| --- | --- | --- |
| [041：动作级间歇与紧凑进展总览](041-action-level-rest-and-compact-progress.md) | 0.0.10 | 两类计划间歇归动作；进展三视图合并为分段卡 |
| [042：用户控制的失败恢复、逐回复反馈与动作图扩容](042-user-controlled-recovery-message-feedback-and-action-art.md) | 0.0.11 | 人工恢复、逐回复反馈、239 图门槛与用户图优先 |
| [043：可配置 ReAct 运行超时](043-configurable-react-runtime-timeout.md) | 0.0.12 | 步骤上限旁增加自动或 3–60 分钟运行超时 |
| [044：行为保持的工程现代化](044-behavior-preserving-modernization.md) | 0.0.12（Unreleased） | 死代码删除、写入路径与带练拆分、3 版本文档窗口；不改变用户可见行为 |

## 阅读约定

- “当前要求”表示仍然有效，并应由当前实现持续满足。
- “被替代”表示曾经实现或讨论过，但已被后续决策取代。
- 产品验收证据集中在 [验收清单](../acceptance.md)。
- 技术与交互取舍集中在 [ADR](../adr/README.md)。
- 按日期重建的变更记录集中在 [Changelog](../changelog/README.md)。
- 新 PRD 从 [模板](template.md) 开始。

## 修订关系

- 旧 PRD 用“后续修订”链接所有改变其边界的新 PRD。
- 新 PRD 用“修订自”反向链接每一份被改变的旧 PRD。
- 部分修订只改变明确段落，其余旧要求继续有效；索引阶段必须与文档头部状态一致。
- 双向链接由 `make check` 自动验证，不能只在正文或本索引单向提及。
- 生命周期门禁仍扫描归档原文；不要为了通过检查而改写归档决策正文。
