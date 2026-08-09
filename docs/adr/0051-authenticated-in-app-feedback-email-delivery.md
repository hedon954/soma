# ADR 0051：认证的应用内反馈邮件投递

- 状态：部分已替代
- 日期：2026-08-09
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：[ADR 0052](0052-gmail-self-delivery-for-in-app-feedback.md) 替代邮件供应商与幂等边界
- 上游依据：[PRD 023](../prd/023-in-app-multimodal-feedback.md)

## 背景

应用内一键发送文字、照片和视频不能依赖 `mailto` 或系统邮件编辑器。客户端若直接连接 SMTP
或邮件 API，就必须携带可提取的发件凭据；自建一套反馈数据库和运营后台又超出当前需求。
Soma 已有带 App Attest/匿名设备签名、临时对象存储和内容清理的 Server 边界，可以承接最小
的邮件投递适配器。

## 决策

- iOS 使用构建时通过 `SOMA_FEEDBACK_BASE_URL` 注入的官方 Soma Server 地址和匿名设备身份，
  调用认证的 `POST /v1/feedback`。反馈不读取用户可编辑的远程 Agent 地址。
- 多媒体沿用签名上传 grant、大小/摘要校验和对象删除机制；反馈端点只接受已完成且属于当前
  设备的 upload ID。
- 服务端使用 Resend Email API，把正文和附件投递到固定收件人 `hedonwang@gmail.com`。
  API Key 与已验证发件地址分别由 `SOMA_FEEDBACK_RESEND_API_KEY`、`SOMA_FEEDBACK_FROM`
  注入，不进入仓库和客户端。
- App 为同一草稿保留稳定 UUID；Server 把 `feedback/{deviceID}/{feedbackID}` 作为邮件服务的
  Idempotency-Key。附件以确定性文件名和 Base64 内容发送，使相同草稿重新上传后仍保持相同
  邮件 payload。
- 单次限制为 5,000 字、10 项附件、25 MB 原始附件总量。25 MB 为 Base64 膨胀和邮件服务
  40 MB 上限保留余量。
- 投递成功后 Server 立即标记并删除临时上传；正文和媒体不写入 PostgreSQL。对象删除失败只
  记录错误类别，依靠对象存储生命周期规则兜底，不把已成功的邮件伪装为发送失败。

## 未选择的方案

- `mailto` 或 `MFMailComposeViewController`：仍把用户带入系统邮件编辑流程，不能满足 Soma
  内一个输入区、一次发送的要求。
- 客户端 SMTP、Gmail API 或 Resend API：必须把发件凭据放进可提取的 App 包，违反密钥边界。
- 反馈正文和附件持久化到 PostgreSQL：为单向邮件反馈额外制造第二份内容事实与删除责任。
- 把反馈作为 Agent Job：反馈不需要模型、Tool、Trace 或身体数据上下文，复用 Agent 状态机会
  模糊协议边界。

## 结果

### 正向影响

- 交互停留在 Soma 内，文字和多媒体共享一个输入与发送动作。
- 固定收件人与服务端凭据不可被客户端覆盖；设备签名、大小、类型、摘要和幂等均有门禁。
- Server 不长期保存反馈内容，新增数据面保持最小。

### 成本与限制

- 生产可用性依赖 Soma Server、对象存储、Resend API Key 和已验证发件域名。
- 邮件与附件送达后由收件邮箱和 Resend 保留，不能承诺端到端本地存储。
- 视频受邮件附件大小约束；大于单次上限时用户需要裁剪或减少附件。
- Resend 的幂等窗口为 24 小时；App 不做后台自动重试，降低窗口外重复投递机会。

## 验证

- `FeedbackSubmissionTests` 验证客户端空态、字符数、数量与字节上限。
- `RemoteAgentExecutionTests` 验证反馈请求使用匿名设备签名与稳定 Idempotency-Key。
- `Server/test/server.test.ts` 验证固定收件人、正文/附件转发、摘要校验和成功后清理。
- `make verify`。

## 参考

- [PRD 023](../prd/023-in-app-multimodal-feedback.md)
- [Resend：Send Email](https://resend.com/docs/api-reference/emails/send-email)
- [Resend：Idempotency Keys](https://resend.com/docs/dashboard/emails/idempotency-keys)
