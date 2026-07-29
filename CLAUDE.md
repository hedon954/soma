# Soma Engineering Principles

本文件是 Soma 仓库内所有 coding agent 和贡献者的最高级工程契约。`AGENTS.md`
链接到本文件，使 Codex、Claude Code、Cursor 和其他 Agent 共享同一套规则。

文档职责：

1. `docs/prd/` 定义产品为什么存在、当前要做什么和验收边界。
2. `docs/adr/` 记录长期技术或交互决策，以及未采用方案。
3. `CLAUDE.md` 定义所有开发活动必须遵循的原则。
4. `.claude/skills/` 定义可执行的日常开发与发布 SOP。
5. 代码、测试、Makefile 和 scripts 是可执行事实。

发生冲突时，不要静默绕过约束。先确认当前 PRD 和 Accepted ADR；需要改变长期边界时，
新增 ADR supersede 旧决策。

## Product contract

Soma 是无账户、本地优先、聊天驱动的 iOS 私人身体智能：

```text
自然表达 → 流式 ReAct → 确定性工具 → 可审查记录 → 长期趋势
```

- **Chat first**：文字、照片、视频和语音统一进入教练；不重新增加传统新增表单。
- **Reviewable by design**：AI 写入的业务数据必须能回看、编辑和删除。
- **Local first**：数据库、原始媒体和 API Key 默认留在设备上。
- **Truth over completeness**：用户没有提供的数据保持为空，不能用常见值补齐。
- **Deterministic where possible**：容量、热量、去重等可计算行为由本地规则实现。
- **Private by default**：日志、Issue、截图、测试夹具不得包含真实身体照片、健康记录或密钥。
- **Native and restrained**：优先使用系统交互与 Apple 平台能力，保持低干扰信息层级。
- **Non-diagnostic**：动作、体态和饮食反馈是一般建议，不冒充医疗诊断。
- **Scope discipline**：只实现当前 PRD 或明确需求，不为可能的未来功能预建入口。

当前产品基线见 `docs/prd/004-soma-current-product.md`，验收矩阵见
`docs/acceptance.md`。

## Architecture

当前技术栈和边界：

- SwiftUI + SwiftData，最低 iOS 17。
- `project.yml` 是 Xcode 工程唯一事实来源；`Soma.xcodeproj` 由 XcodeGen 生成，
  不进入 Git。
- `Soma/App` 负责根生命周期和依赖注入。
- `Soma/Models` 负责 SwiftData 模型、值类型和纯派生属性。
- `Soma/Services` 负责 Agent、HealthKit、Keychain、媒体与确定性业务服务。
- `Soma/Views` 负责系统导航、状态呈现、查询和用户意图。
- `Soma/Components` 负责可复用的 UI 与媒体边界。

依赖方向：

```text
App → Views → Services → Models
       ↓          ↓
   Components   Apple / network adapters
```

### Boundary rules

- View 不拼接 LLM 请求、不解释 Tool Call、不保存 API Key。
- OpenAI-compatible 传输与 ReAct 编排留在 Services。
- Agent 业务写入经 `ConversationRecorder` 和固定 Tool Schema 完成。
- Tool 名称、描述、参数 Schema 与输出协议是系统边界，不能由用户提示词覆盖。
- Skills 是可编辑的专业方法，不是任意代码或动态工具。
- SwiftData 的级联删除、当前健身房唯一性和外部数据去重必须由共享规则维护，
  不能在不同 View 中复制出多套逻辑。
- 长期改变数据模型、Agent 协议、隐私边界、外部同步或分发方式前新增 ADR。

## Data truth and privacy

### Structured records

- 未提供或无法可靠识别的训练重量、间歇、时长、评分等字段保存为 `nil`。
- 训练容量只使用完整、有效的 `组数 × 次数 × 外部重量`。
- 热量使用本地 MET 公式；推算时长只用于热量且必须保留推算标记。
- AI 观察、用户明确事实和本地派生值应能区分。
- 每个 AI 生成的业务记录都必须支持 CRUD。

### External imports

- 外部样本先转换为 Soma 模型，再进入列表和统计。
- 每个数据空间、来源和数据流维护独立 cursor/anchor。
- 外部 ID 去重；来源删除需要同步，重复导入不得改变统计。
- Keep/COROS 没有稳定授权直连时只经用户授权的 Apple 健康读取。

### Sensitive data

- 禁止把 API Key、Authorization 头、证书、私钥、provisioning profile 或媒体 Base64
  写入日志、测试、文档和 Git。
- 测试与截图只使用虚构数据和 `Soma/Resources/DemoMedia`。
- GitHub Issue/PR 中不得附真实身体照片、体重历史、健康备注或完整 Agent Trace。
- Keychain 使用 ThisDeviceOnly 可访问级别；远程 AI 默认关闭。
- 新增远程数据流时必须在 PR 中写明发送内容、触发条件、保留策略和失败行为。

## Agent runtime

- 使用 OpenAI-compatible 原生流式 Tool Calling，不要求自定义决策 JSON。
- 每条用户消息是一条 Trace；model、skill、tool、output 是 Span。
- 文本增量和 Span 生命周期以 Event 实时更新 UI。
- thinking/reasoning 当前不展示、不持久化，也不用于工具执行。
- 同一 Trace 的重复业务写入必须幂等。
- 工具错误作为 `role: tool` 返回模型；失败 Trace 必须落盘且能解释。
- 已成功的工具写入不因最终回复失败而伪装为未发生。
- 不增加删除、任意代码、云同步或账户工具，除非新 PRD/ADR 明确授权。

详细协议见 `docs/react-agent.md` 和 ADR-0003 至 ADR-0005。

## Swift and concurrency

- 项目当前保持 Swift 5 language mode；升级 Swift language mode 必须单独验证并记录。
- UI 和 SwiftData `ModelContext` 变更在 `@MainActor`。
- 明确 Task owner、取消点和生命周期；不要用固定 sleep 修复竞态。
- 跨 actor 的值优先使用不可变 `Sendable` struct。
- 不用 singleton 或无边界全局状态规避依赖传递。
- 系统资源获取与释放必须成对：语音任务、视频文件、HealthKit query 和流式请求都要有
  清理或取消路径。
- 错误保留操作上下文，并映射为用户可理解的恢复建议。
- 新文件以 500 行为软上限；现有超长文件是待偿技术债，不是继续扩张的许可。

## UI and accessibility

- 顶层只保留“教练”和“进展”；低频能力进入设置或高级设置。
- 高频上下文可放在输入框附近，低频调试开关不得占用聊天主界面。
- 详情进入即编辑，修改后出现保存；列表删除遵循系统左滑 destructive action。
- 使用系统文本选择、语音、照片选择器、Charts 和 HealthKit 交互。
- 新交互提供 VoiceOver label，支持 Dynamic Type，并验证空态、错误态和长文本。
- 不展示没有用户意义的内部置信度或 Agent 实现细节。
- 视觉修改至少在 iPhone 尺寸模拟器检查浅色/深色、键盘、滚动和安全区。

## Testing and quality

- 数据真值、去重、容量、热量和 Agent Tool Schema 使用确定性单元测试。
- bug 修复先补能复现问题的测试，再修复。
- SwiftData 变更验证演示/个人空间隔离、旧数据兼容或明确的数据重建策略。
- HealthKit 与真机权限无法完全自动化时，补充手工验收步骤。
- 警告、格式、lint、脚本、文档链接、构建和测试都是质量门禁。
- 开发与提交钩子使用快速静态门禁 `make check`。
- 完成代码或基础设施变更前运行包含构建和模拟器测试的 `make verify`。

## Git and pull requests

提交使用 Conventional Commits：

```text
<type>(<scope>): <中文摘要>

<中文正文>
```

- type：`feat`、`fix`、`docs`、`refactor`、`perf`、`test`、`build`、`ci`、
  `chore`、`style`、`revert`。
- scope 使用稳定模块名，如 `coach`、`agent`、`records`、`insights`、`health`、
  `gym`、`ui`、`build`、`release`、`docs`。
- 摘要使用中文动词、无句号、尽量不超过 72 字符。
- 正文说明动机、关键行为和影响；不要机械重复摘要。
- 一个提交表达一个逻辑目的；格式化、重构与功能不要无关混合。
- breaking change 使用 `type(scope)!:` 和 `BREAKING CHANGE:` footer。

PR 使用 `.github/pull_request_template.md`，必须说明用户结果、隐私影响、数据迁移、
验证证据和相关 PRD/ADR。禁止为了通过 CI 禁用检查。

## Version and release

- 版本遵循 SemVer，发布 tag 为 annotated `vMAJOR.MINOR.PATCH`。
- tag、`project.yml` 的 `MARKETING_VERSION` 和 `CHANGELOG.md` 版本一致。
- `CURRENT_PROJECT_VERSION` 是递增构建号。
- GitHub Release 只发布源码和经审阅的变更说明；iOS 安装包不作为未签名附件分发。
- TestFlight 归档必须使用维护者自己的 Apple Team 和签名资产。
- 任何证书、`.p12`、`.mobileprovision` 或 App Store Connect 凭据都不能进入 Git。

发布 SOP 见 `.claude/skills/soma-release/SKILL.md` 和
`docs/engineering/release.md`。

## Commands and generated files

```bash
make setup          # 安装工具、hooks，并生成工程
make generate       # 从 project.yml 生成 Xcode 工程
make build          # 无签名模拟器构建
make test           # 运行模拟器单元测试
make format         # 格式化 Swift
make lint           # SwiftLint、Actions、shell、文档和仓库契约
make check          # 快速静态门禁，不启动 Simulator
make verify         # 静态门禁、构建和模拟器测试
make install-device # 使用本机 Team 签名、安装并启动已连接的 iPhone
make archive        # 使用本机 Team 导出 TestFlight 归档
make clean
```

命令统一复用 Makefile/scripts，不在文档和 CI 中复制不同版本的长 `xcodebuild`
命令。不要提交生成的 `.xcodeproj`、DerivedData、归档、个人数据、密钥或本地 Agent
配置。
