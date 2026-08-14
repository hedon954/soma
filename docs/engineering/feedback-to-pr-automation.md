# Soma 反馈到 Draft PR 自动化

## 目标

Codex 桌面自动化每 3 小时读取一次维护者 Gmail 中的新 Soma 反馈，在隔离 worktree 从最新 `main` 建立
`codex/feedback-*` 分支，并把一封可执行反馈推进到隐私安全、可审阅的 Draft PR。

## 固定流程

1. 只搜索主题或标签明确属于 Soma 的未处理反馈，先按 Gmail message/thread ID 去重。
2. 读取文字与附件前执行隐私检查；真实身体照片、健康记录、密钥、Authorization、完整 Trace
   不得进入仓库、Issue、日志或 PR。附件只用于本次本地分析，不提交。
3. 获取最新 `origin/main`，在自动化专属 worktree 创建 `codex/feedback-<slug>` 分支。
4. 阅读 `CLAUDE.md`、当前 PRD、Accepted ADR 和 `soma-development` skill；冲突时停止实现并在
   Draft PR 说明，而不是静默绕过。
5. 需要改变产品边界时写 PRD；改变长期技术、交互、隐私或分发边界时写 ADR，并补双向生命周期
   链接。README 只更新索引。
6. 先补复现测试，再实施；运行 `make check` 与风险匹配的定向测试，代码／基础设施变更最终运行
   `make verify`。更新 `CHANGELOG.md` 的 Unreleased。
7. 使用中文 Conventional Commit，推送分支并创建 Draft PR；PR 说明用户结果、隐私影响、数据迁移、
   验证证据和关联 PRD/ADR。
8. 只有 Draft PR 成功创建后，才给邮件加“Codex 已处理”标签或保存对应去重标记。

## 权限边界

- 自动化可以读反馈、改当前仓库、提交、推送和创建 Draft PR。
- 自动化不得合并 PR、创建 tag/Release、发布 TestFlight/App Store、安装真机或给外部联系人回信。
- 不明确、互相冲突或涉及医疗诊断、账号／云同步、删除工具、任意代码执行的反馈，只产出分析、
  PRD/ADR 草案或 Draft PR，不擅自扩大授权。
- 个人阶段 iOS 直连 QQ SMTP 只供维护者本人使用。任何 TestFlight、App Store、Ad Hoc 或他人安装
  都必须先运行 `make online-check`，迁移到认证服务端、轮换旧凭据并用虚构内容冒烟测试。

## 运行与验收

- 自动化依赖 Codex 桌面 App、当前 Mac 与 Gmail/GitHub 连接可用；机器休眠时不承诺准时执行。
- 第一次启用前使用一封虚构反馈测试搜索、去重、worktree、验证、Draft PR 与邮件标记全链路。
- 单封失败不应标记已处理；下次可重试同一封，但不得重复创建多个 PR。
- 每次运行摘要至少包含邮件时间、匿名化主题、分支、验证命令、Draft PR 链接或明确阻塞原因。
