# Soma 工程指南

本目录保存可执行工程协议、实施次序、仓库协作、验证和发布流程。产品范围在 `docs/prd/`，
长期决策在 `docs/adr/`；工程文档不得静默改变 PRD/ADR。

- [训练领域模型与运行时协议](training-domain-model.md)
- [Soma UI 设计系统与优化工程报告](soma-ui-design-system.md)
- [数据库结构与 ER 图](database-schema.md)
- [全 App 性能审计报告（2026-08-24）](performance-audit-2026-08-24.md)
- [本轮性能优化收尾与踩坑报告（2026-08-25）](performance-optimization-retrospective-2026-08-25.md)
- [性能优化经验教训：有界数据、渲染隔离与首帧诚实（2026-08-26）](performance-optimization-lessons-2026-08-26.md)
- [真机性能录制：一次安装，多次复用](device-performance-profiling.md)
- [Agent Job 与远程执行协议](agent-job-protocol.md)（视频兼容与错误分类修订：ADR 0131 / 0132）
- [用户错误呈现清单](user-facing-errors.md)
- [Agent Tool 目录](agent-tool-catalog.md)（受控提问工具与确定性按钮：ADR 0136）
- [ReAct Agent](../react-agent.md)（受控提问成功后停止模型循环：ADR 0136）
- [默认 Prompt 来源目录](prompt-source-catalog.md)
- [训练智能与可靠 Agent 实施次序](implementation-sequence.md)
- [训练智能与可靠 Agent 全量 Todo](implementation-todo.md)
- [可选 Agent Server 部署与运维](../../Server/README.md)
- [个人设备 QQ 邮箱反馈配置](personal-feedback-qq-mail.md)
- [Soma 反馈到 Draft PR 自动化](feedback-to-pr-automation.md)
- [仓库与开发工作流](repository-workflow.md)
- [GitHub 仓库设置](github-settings.md)
- [版本、GitHub Release 与 TestFlight](release.md)

Apple 健康每日运动记录见 [数据库结构](database-schema.md) 的 PRD 075 / ADR 0144 边界；新增 WorkoutEntry 可空字段，无新增模型。
