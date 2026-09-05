# BUG 0029：可见失败仍自动重试并残留旧错误

- 状态：已修复，待真机网络故障复验
- 日期：2026-08-23
- 下游落地：
  - [PRD 042](../archive/0.0.11/prd/042-user-controlled-recovery-message-feedback-and-action-art.md)
  - [ADR 0092](../archive/0.0.11/adr/0092-react-internal-retry-and-user-controlled-recovery.md)
  - [PRD 048](../archive/0.0.17/prd/048-reviewable-record-derivation-and-user-controlled-interruption.md)
  - [ADR 0106](../archive/0.0.17/adr/0106-reviewable-derived-records-and-manual-interruption.md)

## 症状

Agent 已显示“执行失败”后仍可能因网络、前台、配置变化或计时器自动继续。后续成功回复会与旧网络
错误文字同时存在，且失败卡下方另有一个大号文字重试按钮。

## 根因

模型步骤内部、Job failure disposition、远程 SSE 和 RootView 配置通知各自拥有恢复逻辑；自动恢复
提示被当作成功文字 item 保存，同气泡 resume 只按成功状态筛选，因而保留了等待/错误文案。

## 修复

- 自动退避集中到 ReAct 模型步骤，固定三次 1/2/4 秒；Loop 外全部进入人工恢复。
- 删除 Service retry task、供应商 staging delay、配置变化自动释放和远程网络自动续跑。
- 手动重试复用同一气泡并先清理 error/running/失败文字；失败卡右侧只保留图标按钮。

## 回归门禁

- `AgentV2Tests` 验证三次指数退避和第四次请求成功。
- `LLMOutageStagingTests` 验证所有 Loop 外瞬态失败等待用户，`waitingForNetwork` 不可自动领取。
- `RecordMutationTests` 验证恢复投影删除失败卡并保留成功 Tool step。
- 真机断网、恢复网络、切前后台和保存配置均不得自动发起失败 Turn；点按图标后最终界面不留旧错误。
