# ADR 0010：统一仓库契约、质量门禁与 XcodeGen 事实来源

- 状态：已采纳
- 决策日期：2026-07-29

## 背景

Soma 即将进入 GitHub，并由多个 coding agent 和人类贡献者持续迭代。若 Xcode 工程、
构建命令、Agent 规则和 CI 分别维护，会快速出现“本机能跑、CI 不能跑”或不同 Agent
遵守不同产品边界的问题。

## 决策

1. `CLAUDE.md` 是 canonical 工程契约，`AGENTS.md` 链接到它。
2. `.claude/skills` 是项目 Skill 唯一来源，Codex 与 Cursor 目录链接到它。
3. `project.yml` 是 Xcode 工程唯一事实来源，生成的 `.xcodeproj` 不进入 Git。
4. Makefile/scripts 是所有本地和 CI 命令的唯一入口。
5. `make check` 统一执行格式、lint、仓库契约、secret、构建和测试。
6. GitHub CI 对 main/PR 执行同一门禁；公开仓库额外执行 Swift CodeQL 与依赖审查。
7. GitHub Release 只发布源码元数据；TestFlight 签名留在维护者控制环境。
8. 根 `CHANGELOG.md` 管版本，`docs/changelog/` 保留产品迭代历史。

## 未选择的方案

- 提交生成的 Xcode 工程：容易与 `project.yml` 漂移并产生不可审查的 pbxproj 噪声。
- 每种 Agent 维护独立规则：内容会逐渐冲突。
- 在 workflow 复制长 xcodebuild 命令：本地与 CI 会形成两条构建路径。
- 把 Apple 签名资产放进 GitHub：当前收益不足以覆盖凭据泄漏与轮换成本。
- 首次接入门禁时强制重构全部超长文件：扩大无关变更并增加产品回归风险。

## 结果

- 新环境运行 `make setup` 即可获得一致工程和 hooks。
- 所有贡献在 PR 前后经过同一 `make check`。
- XcodeGen 和仓库契约成为显式、可验证的开发基础设施。
- 现有超长文件通过兼容首版的 lint ceiling 进入门禁，后续遵循 500 行软限制逐步拆分。
- GitHub 远端仍需按 `docs/engineering/github-settings.md` 启用 ruleset 和安全开关。
