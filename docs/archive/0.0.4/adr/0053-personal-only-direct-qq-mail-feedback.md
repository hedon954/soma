# ADR 0053：个人阶段直连 QQ 邮箱的反馈投递

- 状态：已采纳，仅限个人使用阶段
- 日期：2026-08-10
- 维护者：Soma maintainers
- 部分替代：[ADR 0051](0051-authenticated-in-app-feedback-email-delivery.md) 的当前投递路径与构建地址；[ADR 0052](0052-gmail-self-delivery-for-in-app-feedback.md) 的个人阶段邮件供应商与凭据位置
- 后续替代：
  - 对外分发前必须由新的服务端凭据边界 ADR 替代
  - [ADR 0093](../../0.0.11/adr/0093-bounded-per-reply-multimodal-feedback-context.md) 为用户主动发起的逐回复反馈增加单 Turn 可见文本与脱敏执行摘要
  - [ADR 0083](../../0.0.7/adr/0083-local-diagnostics-log-and-silent-crash-reporting.md) 在同一投递链路上增加默认
    静默的崩溃诊断报告；「邮件只承载用户明确填写内容」的边界不再覆盖全部出网邮件
- 上游依据：[PRD 023](../prd/023-in-app-multimodal-feedback.md)

## 背景

Soma 当前只能由维护者本人安装使用。维护者明确接受个人阶段把 QQ 邮箱 SMTP 授权码随本机
安装包携带，以避免为反馈部署 Server；同时要求反馈 UI 不显示邮箱、SMTP 或认证实现。这个
例外不能延伸到 TestFlight、App Store 或任何外部用户。

## 决策

- iOS 通过 TLS 连接 `smtp.qq.com:465`，以 QQ 邮箱地址和 SMTP 授权码认证，并把反馈发送到
  代码中固定的 `hedonwang@gmail.com`。
- 反馈页只展示说明、文字与媒体输入、发送动作和结果，不提供或解释邮箱、SMTP、Server 与
  凭据细节。
- `FeedbackCredentials.plist` 只保存 `SenderAddress` 和 `SMTPAuthorizationCode`。该文件被
  Git 忽略，禁止进入源码、日志和文档。
- 当前链路不调用 Soma Server，不写入身体数据库、聊天或 Agent Trace。App 在内存中生成
  RFC 2822/MIME 邮件并直接通过 SMTP 发送。
- `make online-check` 在客户端仍携带邮件凭据时故意失败，并阻止 TestFlight 归档。仅含源码的
  GitHub Release 不受影响。

## 未选择的方案

- 当前立即部署完整 Soma Server：个人单设备阶段的运维成本高于收益。
- 在反馈页增加邮箱或服务器设置：暴露内部实现并增加无意义的用户决策。
- 把真实授权码提交到源码：Git 历史不可安全撤回。
- 把个人阶段例外用于外部用户：安装包无法保守共享的 SMTP 授权码。

## 结果

### 正向影响

- 个人设备无需部署反馈 Server，仍可在 Soma 内直接发送文字、照片和视频。
- UI 保持单一，邮箱变化不成为用户设置。
- 仓库不保存真实 QQ 邮箱凭据。

### 成本与限制

- 个人安装包内的授权码可以被提取，该风险只由个人使用的临时边界承担。
- 凭据缺失、撤销或过期时只显示通用失败并保留草稿。
- 对外开放前必须迁移凭据、删除客户端配置并轮换 SMTP 授权码。

## 验证

- `FeedbackSubmissionTests` 验证配置解析、固定 Gmail 收件人、QQ 发件人和 MIME 文字/附件。
- `make verify` 通过；真机使用虚构内容确认 QQ“已发送”和 Gmail 收件箱均收到邮件。
- `make online-check` 在当前个人直连阶段必须失败。

## 参考

- [个人设备 QQ 邮箱反馈配置](../../../engineering/personal-feedback-qq-mail.md)
