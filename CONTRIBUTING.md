# Contributing to Soma

感谢帮助 Soma 变得更可靠。开始前请阅读：

1. [工程契约](CLAUDE.md)
2. [当前 PRD](docs/prd/004-soma-current-product.md)
3. [Accepted ADR](docs/adr/README.md)
4. [验收清单](docs/acceptance.md)

## 本地准备

需要 macOS、Xcode、Homebrew 和至少一个可用的 iPhone Simulator。

```bash
make setup
make check
make verify
```

`make setup` 安装 Brewfile 工具、pre-commit hooks，并从 `project.yml` 生成
`Soma.xcodeproj`。生成的工程不会提交到 Git。

## 变更流程

1. 先描述用户问题、成功路径、失败状态与隐私影响。
2. 只实现当前 PRD 内最小的可验证闭环。
3. 长期改变 Agent 协议、数据模型、同步、隐私或分发方式时先提交 ADR。
4. 行为变更补充确定性测试；硬件能力补充手工验收说明。
5. 开发中运行 `make format` 和 `make check`；提交 PR 前运行 `make verify`。
6. 使用中文 Conventional Commit，并通过 PR 模板提交。

## 隐私要求

永远不要在提交、Issue、PR、截图或测试中包含：

- 真实体态/身体照片或训练视频；
- 真实体重、体脂、健康备注或 Apple 健康导出；
- API Key、Authorization 头或完整私有 Agent Trace；
- 证书、私钥、Provisioning Profile 或 App Store Connect 凭据。

只能使用 `Soma/Resources/DemoMedia` 和虚构数据演示问题。

## 代码范围

- 创建行为从聊天进入；列表和详情负责审查与纠错。
- 未提供字段保持为空。
- 业务写入使用固定原生 Tool Calling。
- 外部导入必须归一化、保存游标、按外部 ID 去重并处理删除。
- 新文件以 500 行为软上限；避免继续扩大现有超长文件。

完整日常 SOP 见 `.claude/skills/soma-development/SKILL.md`。
