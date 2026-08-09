# ADR 0052：Gmail 自发自收应用内反馈

- 状态：已采纳
- 日期：2026-08-09
- 维护者：Soma maintainers
- 部分替代：[ADR 0051](0051-authenticated-in-app-feedback-email-delivery.md) 的邮件供应商与幂等边界
- 后续替代：暂无
- 上游依据：[PRD 023](../prd/023-in-app-multimodal-feedback.md)

## 背景

PRD 023 要求反馈留在 Soma 内完成，ADR 0051 因此建立了认证 Server、临时附件和固定收件人的
投递边界。维护者进一步明确要求邮件必须从 `hedonwang@gmail.com` 发给同一邮箱。第三方邮件
供应商无法代表未由维护者控制域名的 `gmail.com` 地址发信；客户端直接持有 Gmail 凭据也会
暴露可提取的长期授权。

## 决策

- 保留 ADR 0051 的 App 交互、匿名设备认证、`POST /v1/feedback`、临时对象存储和成功后清理。
- Server 使用 Gmail API `users.messages.send`，发件人与收件人均硬编码为
  `hedonwang@gmail.com`，客户端请求不能覆盖。
- 维护者一次性授权 `https://www.googleapis.com/auth/gmail.send` 离线访问。OAuth client ID、
  client secret 与 refresh token 分别由 `SOMA_FEEDBACK_GMAIL_CLIENT_ID`、
  `SOMA_FEEDBACK_GMAIL_CLIENT_SECRET`、`SOMA_FEEDBACK_GMAIL_REFRESH_TOKEN` 注入服务端
  secret manager，不进入 iOS、日志或 Git。
- 每次投递先用 refresh token 向 Google OAuth token endpoint 换取短期 access token，再把
  RFC 2822/MIME 邮件以 `message/rfc822` 简单媒体上传发送；正文与附件不经 JSON 双重 Base64。
- 稳定反馈 ID 继续映射为确定性的 RFC Message-ID，便于识别同一草稿重试。Gmail API 没有
  Resend 的 Idempotency-Key 契约，因此不宣称严格去重；App 不做后台自动重试，失败由用户
  明确触发重试。
- 单次附件原始总量继续限制为 25 MB，与个人 Gmail 多附件总上限对齐；图片和视频仍受既有
  类型、大小、所有权与摘要校验。

## 未选择的方案

- 客户端 Gmail API：OAuth client secret 和 refresh token 会进入可提取的 App 包。
- Gmail SMTP App Password：长期密码权限更宽、轮换和撤销边界弱于最小 `gmail.send` scope。
- Google service account：个人 Gmail 不提供 Workspace 域级委派，不能据此代表该邮箱发送。
- Resend 等第三方发件人：不能合法验证和代表 Google 管理的 `gmail.com` 域。

## 结果

### 正向影响

- 收到的反馈邮件具有维护者要求的同一 Gmail 发件人与收件人。
- Gmail 长期授权只存在服务端；App 仍只知道官方 Soma Server 地址。
- 原始 MIME 直接上传避免附件内容在邮件 JSON 内再次 Base64 膨胀。

### 成本与限制

- 生产启用前必须创建 Google Cloud OAuth client、启用 Gmail API，并由维护者完成一次
  `gmail.send` consent 取得 refresh token。
- refresh token 被撤销、长期未使用或 OAuth 应用处于不稳定授权状态时，发送会失败并保留
  App 草稿供用户重试。
- Gmail API 不提供提交幂等键；稳定 Message-ID 不是严格去重保证。

## 验证

- `Server/test/server.test.ts` 验证 OAuth refresh 参数、Bearer access token、
  `message/rfc822` 投递、固定 From/To、UTF-8 正文和附件 MIME。
- `make verify`。
- 生产冒烟测试使用虚构文字和演示媒体，确认同一 Gmail 的 Inbox 与 Sent 均出现邮件；不得用
  真实身体或健康材料测试。

## 参考

- [PRD 023](../prd/023-in-app-multimodal-feedback.md)
- [Google：Gmail API 发送邮件](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send)
- [Google：Gmail API 上传附件](https://developers.google.com/workspace/gmail/api/guides/uploads)
- [Google：服务端 OAuth](https://developers.google.com/workspace/gmail/api/auth/web-server)
