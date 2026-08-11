# ADR 0054：设备执行的聊天反馈 Tool

- 状态：已采纳
- 日期：2026-08-11
- 维护者：Soma maintainers
- 部分替代：[ADR 0050](0050-per-turn-tool-group-exposure-and-parallel-calls.md) 的固定工具组列表，新增 `feedback` 组
- 上游依据：[PRD 024](../prd/024-chat-agent-feedback-tool.md)

## 背景

PRD 023 与 ADR 0053 已提供设置页反馈和个人阶段 QQ SMTP 投递。用户进一步要求在教练 Chat
中直接提交反馈。这个入口属于 Agent 固定 Tool 协议，必须同时解决模型可控内容、当前消息媒体
归属、异步 SMTP 结果、Turn 重试幂等和远程 Agent 的设备权限边界。

## 决策

1. 固定新增 mutation Tool `submit_feedback`，JSON Schema 为无参数对象。模型只能决定是否
   调用，不能改写邮件正文、传入文件路径、邮箱、URL 或凭据。
2. Tool 只在用户当前消息明确要求提交 Soma 产品反馈时暴露；本机工具组新增 `feedback`，由
   确定性产品反馈关键词预选，也可经 `expand_tool_group` 显式展开。
3. 执行器从当前 Turn 的 `CoachMessage.text` 和 `AgentJob.mediaAttachments` 构造反馈；不读取
   历史消息、Agent 上下文包或业务数据库。
4. ReAct 的 Tool 执行闭包升级为 `async throws`。SMTP 完成后才返回成功；取消向上抛出，普通
   投递错误以失败 Tool result 返回模型。
5. `AgentMutationReceipt` 在外部投递前写入 pending，成功后 committed，失败或取消删除；同一
   Turn 的恢复不重复成功调用。SMTP 接收与本机 committed 之间仍是至少一次边界，稳定
   Message-ID 用于识别极小崩溃窗口中的重复邮件。
6. 远程 Agent Registry 同步注册同名 Tool，但执行位置仍是设备：服务器生成 device Tool
   request，设备在 `waitingForDevice` 中完成投递并返回结果。QQ 凭据不上传 Soma Server。
7. Tool Trace 只记录空参数、名称和通用结果，不记录反馈正文、媒体内容或认证信息。

## 未选择的方案

- 让模型传 `message`：模型可能总结、补写或带入历史上下文，破坏“只发送用户明确内容”。
- 自动附加最近聊天、Trace 或日志：扩大隐私数据流，且用户无法在发送前准确审查。
- fire-and-forget 后立即返回成功：SMTP 失败时会向用户报告虚假成功。
- 远程 Server 直接执行个人 QQ SMTP：会把个人阶段凭据扩大到新的服务端边界，并违背
  `waitingForDevice` 权限模型。

## 结果

- Chat 与设置页共用一个确定性反馈投递服务，用户无需重复录入。
- Agent 只能提交当前消息的原文和媒体，Trace 与服务器都不获得反馈正文副本以外的新数据面。
- ReAct Tool runner 支持真实异步副作用，现有同步 Tool 继续通过同一 async closure 顺序执行。

## 验证

- Swift 测试固定 Tool Schema、工具组预选、当前 Turn 原文/媒体转换、SMTP 成功/失败与异步
  mutation receipt。
- Server 测试固定 Registry 接受 `submit_feedback` 空参数并拒绝路径或未知参数。
- `make verify` 与虚构内容真机聊天投递。
