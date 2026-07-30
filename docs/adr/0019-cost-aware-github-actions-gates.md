# ADR 0019：GitHub Actions 按成本分层执行质量门禁

- 状态：已采纳
- 日期：2026-07-30
- 部分替代：[ADR 0011](0011-fast-check-full-verify.md) 的 GitHub 自动执行范围

## 背景

Soma 的 iOS 构建和模拟器测试只能运行在 macOS runner。2026 年 7 月 30 日的近期成功记录
显示，每次推送到 `main` 的完整 CI 约占用 6 至 9 分钟 macOS runner，其中
`make verify` 约占 6 分钟。连续推送还产生了多次已经开始计费、随后才被并发策略取消的运行。

GitHub 托管 macOS runner 的单位成本显著高于标准 Linux runner。对本地优先的个人仓库，
每次 `main` 推送重复执行完整模拟器验证会快速耗尽 Actions 额度，但直接取消格式、lint、
文档、secret 和仓库契约检查又会失去及时反馈。

## 决策

1. 本地命令语义不变：
   - `make check` 是快速静态门禁；
   - `make verify` 包含静态门禁、无签名构建和模拟器单元测试。
2. coding agent、贡献者和 pre-push/交付流程继续在本地执行 `make verify`；节省云端额度不能
   用来降低本地完成标准。
3. `ci.yml` 在 PR 和 `main` 推送时只运行 `make check`，继续使用并发取消，但不启动
   Xcode build 或 Simulator。
4. `release.yml` 在 `v*` tag 时先用低成本脚本验证 tag、版本和 Changelog，再运行完整
   `make verify`；全部通过后才创建 GitHub Release。
5. `security.yml` 的 Dependency Review 只在公开仓库 PR 上运行；Swift CodeQL 只在公开
   仓库的 `v*` tag 或人工 `workflow_dispatch` 上运行，不再随 `main` 推送或每周定时运行。
6. 日常 GitHub 静态检查的 required status 使用 `Fast static quality gates`。仓库套餐不支持
   ruleset 时，以本地 pre-commit、交付前 `make verify` 和 release tag 门禁组成闭环。

## 风险与补偿

- PR 或 `main` 上的 Swift 编译错误不会再由云端即时发现。补偿措施是本地完成定义强制
  `make verify`，release tag 再次执行同一完整命令。
- CodeQL 的反馈频率降低。Soma 不在 GitHub Actions 中处理签名资产、真实健康数据或运行时
  密钥；release tag 仍保留完整 CodeQL 边界，必要时可以人工触发。
- release tag 才发现失败会阻止 Release 创建，但不会污染已有源码提交或设备数据。

## 未选择的方案

- 每次 `main` 继续完整验证：保护最强，但已证实额度不可持续。
- 完全关闭 GitHub Actions：失去静态契约、release 元数据和发布前最后门禁。
- 把 iOS 构建迁移到 Linux：SwiftUI、SwiftData、HealthKit 和 iOS Simulator 无法由 Linux
  runner 等价验证。
- 引入常驻 self-hosted Mac：需要额外维护在线状态、隔离、升级和凭据边界，当前收益不足。

## 结果

- 日常推送仍能快速发现格式、lint、workflow、shell、文档、secret 和仓库契约错误。
- macOS 上耗时最长的构建、模拟器测试和 CodeQL 从高频推送移到低频 release tag。
- 本地完整验证仍是开发完成条件；GitHub Release 仍由完整验证结果保护。

## 参考

- [GitHub Actions workflow 触发与 branch/tag 过滤](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [GitHub-hosted runner 规格与额度说明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)
