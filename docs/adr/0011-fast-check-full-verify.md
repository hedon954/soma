# ADR 0011：分离快速静态检查与完整模拟器验证

- 状态：部分已替代
- 决策日期：2026-07-29
- 部分替代：[ADR 0010](0010-repository-governance-and-xcodegen.md) 的质量命令分层
- 后续替代：[ADR 0019](0019-cost-aware-github-actions-gates.md) 调整 GitHub 自动触发层级，本地命令语义保持不变

## 背景

初始仓库把格式、lint、构建和模拟器单元测试全部放进 `make check`，并让 pre-commit
执行该命令。iOS 冷缓存构建和 Simulator 测试耗时明显高于静态检查，导致每次 commit
都承担完整 CI 成本，不利于高频、小步开发。

完整行为测试仍然必要。Soma 的 SwiftData、ReAct Tool 写入、数据空间隔离、去重、容量
和热量规则不能只靠格式、lint 或编译证明，因此不能从 CI 和发布门禁移除模拟器测试。

## 决策

1. `make check` 是快速静态门禁：环境、格式、lint、脚本、文档、仓库契约和 secret。
2. pre-commit 只执行 `make check`，不启动 Simulator。
3. `make verify` 先执行 `make check`，再执行无签名构建和模拟器单元测试。
4. GitHub CI、GitHub Release、PR 前验收和交付完成条件执行 `make verify`。
   GitHub 自动执行范围后由 ADR 0019 调整；本地 PR 前验收和完整交付仍执行该命令。
5. `make build` 与 `make test` 保留为可独立调用的窄命令。

## 未选择的方案

- 完全取消模拟器测试：只能缩短 CI，无法保护数据与 Agent 的确定性行为。
- 每次 commit 都执行完整测试：反馈更强，但与 iOS 工具链成本不成比例。
- 把业务测试改为纯 macOS Swift Package：长期可能有价值，但当前模型依赖 SwiftData、
  SwiftUI、HealthKit 和 iOS App 生命周期，迁移会扩大本次基础设施调整。

## 结果

- 日常 `make check` 和 commit 明显更快，不要求启动 Simulator。
- PR、main、发布和 Coding Agent 交付仍由构建与 32 个单元测试兜底。
- 命令名称表达验证强度，避免把“静态检查通过”误报成“App 行为已经验证”。
