# 仓库与开发工作流

## 事实来源

| 内容 | 唯一事实来源 |
| --- | --- |
| 产品当前范围 | `docs/prd/004-soma-current-product.md` |
| 长期决策 | `docs/adr/README.md` |
| 工程规则 | `CLAUDE.md` |
| Agent 日常 SOP | `.claude/skills/soma-development/SKILL.md` |
| Xcode 工程 | `project.yml` |
| 本地与 CI 命令 | `Makefile` 和 `scripts/` |
| 发布内容 | `CHANGELOG.md` |

`AGENTS.md`、`.cursor/skills` 和 `.codex/skills` 都链接到 canonical 文件，避免不同
coding agent 得到漂移的规则。

## 首次准备

```bash
make setup
```

它会：

1. 使用 `brew bundle` 安装 XcodeGen、SwiftFormat、SwiftLint、actionlint、
   shellcheck 和 pre-commit；
2. 安装 Git hooks；
3. 从 `project.yml` 生成本地 `Soma.xcodeproj`。

## 日常循环

```bash
make generate       # 依赖或 target 变化后
make build
make test
make format
make check          # 开发与 commit 前的快速静态门禁
make verify         # PR、发布与完整交付前

# 连接已开启开发者模式的 iPhone 后
DEVELOPMENT_TEAM=你的TeamID make install-device
```

`make check` 不启动 Simulator，适合高频本地循环和 pre-commit：

1. 环境检查；
2. SwiftFormat lint；
3. SwiftLint；
4. GitHub Actions 和 shell 脚本静态检查；
5. Agent/ADR/隐私/文档链接/secret 仓库契约。

`make verify` 先执行 `make check`，再执行：

1. 无签名 iOS Simulator 构建；
2. 模拟器单元测试。

GitHub CI、发布流程和完整交付验收统一运行 `make verify`。

`make install-device` 不属于 CI 门禁。它使用 Automatic Signing 为主 App 与 Widget
Extension 签名，把 Debug 构建安装到已连接的 iPhone，并在安装后启动 Soma。设备自动选择
失败时可通过 `SOMA_DEVICE_ID` 显式指定 UDID；证书、Team 和设备注册仍由本机 Xcode
账号管理。

## 生成物与密钥

以下内容只存在本机：

- `Soma.xcodeproj`、DerivedData、`.xcresult`、archive 和 IPA；
- Apple 证书、私钥和 provisioning profile；
- API Key、本地 Agent 配置和个人数据；
- Xcode/Simulator/Codex 本地状态。

如果 CI 与本机结果不同，先比较 `xcodebuild -version`、`project.yml` 和
`make verify` 输出，不要提交生成工程来“修复”漂移。

## 已知技术债

部分首版 View 和 Service 文件超过 500 行。SwiftLint 暂时使用可通过首版代码的上限，
但 `CLAUDE.md` 对新文件设置 500 行软限制。后续在修改相关功能时按职责逐步拆分，不进行
与业务变更无关的一次性大重构。
