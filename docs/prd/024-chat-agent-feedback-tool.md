# PRD 024：聊天内 Agent 反馈 Tool

- 状态：已实现，待真机验收
- 日期：2026-08-11
- 修订自：[PRD 004](004-soma-current-product.md) 的聊天与隐私边界；[PRD 022](022-react-reliability-and-context-awareness.md) 的工具组；[PRD 023](023-in-app-multimodal-feedback.md) 的反馈入口与投递规则
- 上游依据：维护者明确要求用户可直接在 Chat 中提交反馈
- 后续修订：
  - [PRD 033](033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md) 在同一投递链路上
    增加默认静默的崩溃诊断上报；用户明确提交才发送的边界只覆盖反馈本身
- 下游落地：[ADR 0054](../adr/0054-device-executed-chat-feedback-tool.md)

## 用户结果

1. 用户在教练聊天当前消息中明确提出“提交产品反馈”时，Agent 可调用固定
   `submit_feedback` Tool，无需再进入设置页重复填写。
2. Tool 成功后，聊天中的 Tool 结果明确显示反馈已经发送；失败时说明暂时无法发送，Agent
   不得把失败描述成成功。
3. 设置页原有文字与多媒体反馈入口继续保留，两条入口共用相同限制和 QQ→Gmail 投递服务。

## 产品规则

- `submit_feedback` 没有模型可填写的正文参数。邮件正文固定使用触发 Tool 的当前用户消息
  原文，附件固定使用当前消息中用户明确选择的照片和视频。
- 只有当前消息明确要求向 Soma 维护者提交产品反馈时才能调用。训练动作反馈、饮食建议、身体
  观察或一般“给我反馈”不是产品反馈，不得调用。
- Tool 不引用更早消息；用户希望反馈历史问题时，需要在当前消息中重新写明要提交的内容。
- 文字、附件数量和附件大小继续遵守 PRD 023 的 5,000 字、10 项、25 MB 上限。
- 当前 Turn ID 作为反馈 ID 和稳定 Message-ID。同一 Turn 已成功投递后，重试或恢复复用本机
  mutation receipt，不再次发送；SMTP 在“邮件已接受但回执未落盘”的崩溃窗口仍不保证严格
  exactly-once。

## 本机与远程执行

- 本机 ReAct 等待 SMTP 投递结果后才形成 Tool 结果，不使用 fire-and-forget Task。
- 后台持续模式的远程 Agent 只生成固定设备 Tool 请求；设备进入 `waitingForDevice` 后读取当前
  Turn 的本机原文与媒体并执行投递，服务器不接收 SMTP 凭据，也不代替设备发送。
- 设备离线、凭据不可用、媒体丢失或 SMTP 失败时返回失败结果，由用户明确重试。

## 数据与隐私

- Tool 只发送当前用户消息原文和当前消息附件，不自动附加历史聊天、Agent 回复、上下文包、
  SwiftData 记录、位置、Trace、日志、API Key 或其他凭据。
- Tool 调用名称、成功/失败状态和通用结果进入 Agent Trace；反馈正文、媒体 Base64、QQ 地址与
  SMTP 授权码不得进入 Tool 参数、Trace input/output 或日志。
- 当前个人阶段继续遵守 ADR 0053：凭据只在被 Git 忽略的本机配置中，外部分发前必须通过
  `make online-check` 迁移凭据边界。

## 验收

- “把这个按钮点不动的问题提交反馈”会暴露并调用 `submit_feedback`；普通“请评价我的深蹲
  动作”不会暴露或调用产品反馈 Tool。
- 纯文字以及当前消息带图片、视频或混合媒体均复用现有反馈限制并发送到固定 Gmail。
- Tool Schema 无正文、路径、URL、邮箱或认证参数；模型不能选择历史媒体。
- 本机与远程设备 Tool handoff 都等待实际结果；成功幂等、失败可重试、取消不留下 committed
  receipt。
- `make verify` 通过；真机只用虚构内容完成一次聊天提交与 Gmail 收件验收。
