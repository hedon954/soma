# Soma Engineering Principles

本文件是 Soma 仓库内所有 coding agent 和贡献者的最高级工程契约。`AGENTS.md`
链接到本文件，使 Codex、Claude Code、Cursor 和其他 Agent 共享同一套规则。

文档职责：

1. `docs/prd/` 定义产品为什么存在、当前要做什么和验收边界。
2. `docs/adr/` 记录长期技术或交互决策，以及未采用方案。
3. `docs/bugs/` 记录关键故障的机制、修复与可执行回归门禁。
4. `CLAUDE.md` 定义所有开发活动必须遵循的原则。
5. `.claude/skills/` 定义可执行的日常开发与发布 SOP。
6. 代码、测试、Makefile 和 scripts 是可执行事实。
7. `.codex|.cursor|.claude/plans/` 记录所有 Agent 的调研与开发计划。

发生冲突时，不要静默绕过约束。先确认当前 PRD 和 Accepted ADR；需要改变长期边界时，
新增 ADR supersede 旧决策。

### Document lifecycle

- PRD、ADR、Bug、Research 和工程协议发生修订、部分替代或替代时，必须建立双向索引：
  旧文用“后续修订”“后续替代”或“下游落地”链接新文，新文用“修订自”“替代”
  “部分替代”或“上游依据”链接旧文。
- 双向关系必须同时出现在文档头部，并同步对应目录的 README 索引；不能只在正文里单向提及。
- 一份新文影响多个旧决策时逐项链接；旧文只标记被改变的部分，不因局部修订隐藏仍有效内容。
- 生命周期索引只覆盖已经进入 Git 的决策。工作区中尚未提交、又被后续实现替换的代码、测试和
  文档直接删除，不留“曾经有过 / 现已删除 / 不再兼容 / 隐藏路径”等过渡说明。只有 HEAD 里
  已有的 PRD、ADR、Bug 或工程协议被这次提交改变时，才建立后续修订或替代关系。
- `scripts/check-document-lifecycle-links.rb` 是双向关系的自动门禁。新增生命周期链接时必须让
  `make check` 验证反向边存在。门禁验证**活文档**互链；`docs/archive/` 原文是考古，不要求与
  活文档互链。
- **活文档窗口**：`docs/prd/` 与 `docs/adr/` 的阅读顺序是「压缩起点 → 最近 3 个营销版本」
  （以 `project.yml` 的 `MARKETING_VERSION` 与 `CHANGELOG.md` 版本标题为准，不按文件日期）。
  压缩起点（`docs/prd/000-origin-through-0.0.11.md`、`docs/adr/0000-origin-through-0.0.11.md`）
  是滑出窗口内容的滚动收口：只保留仍有效的最终要求与决策，不是旧文件清单。窗口最旧活文档的
  修订自 / 部分替代指向压缩起点；起点没有更早的活前驱。
- **发布时合并，不要只搬家**：每次新 App 发布，把滑出窗口的原文 `git mv` 进
  `docs/archive/<version>/`，并把「现有压缩起点 + 该版本仍有效的最终状态」合并成新起点，
  替换旧起点。归档留在 Git，不加入 gitignore。这与 Agent 消息滚动压缩相同。
- **不要默认读取 `docs/archive/`**，除非维护者明确要求查阅历史。Cursor 使用根
  `.cursorignore`；Claude Code 使用 `.claude/settings.json` 的 `Read(./docs/archive/**)`
  deny；Codex 没有可靠的 `.codexignore`（openai/codex#24993 仍开放），必须遵守本条。
  不要新增 `.claudeignore` 或 `.codexignore` 作为替代。

## Product contract

Soma 是无账户、本地优先、聊天驱动的 iOS 私人身体智能：

```text
自然表达 → 流式 ReAct → 确定性工具 → 可审查记录 → 长期趋势
```

- **Chat first**：文字、照片、视频和语音统一进入教练；不重新增加传统事实新增表单。训练计划
  这类显式授权的结构化编排可使用专用 GUI，但必须与聊天共用同一数据与验证边界。
- **Reviewable by design**：AI 写入的业务数据必须能回看、编辑和删除。
- **Local first**：业务数据库、原始媒体和用户自带的 API Key 默认留在设备上；可选远程
  执行只能由明确 PRD/ADR 授权，且服务器不能成为身体业务数据的默认事实来源。
- **Truth over completeness**：用户没有提供的数据保持为空，不能用常见值补齐。
- **Deterministic where possible**：容量、热量、去重等可计算行为由本地规则实现。
- **Private by default**：日志、Issue、截图、测试夹具不得包含真实身体照片、健康记录或密钥。
- **Native and restrained**：优先使用系统交互与 Apple 平台能力，保持低干扰信息层级。
- **Non-diagnostic**：动作、体态和饮食反馈是一般建议，不冒充医疗诊断。
- **Scope discipline**：只实现当前 PRD 或明确需求，不为可能的未来功能预建入口。

当前产品不变量以本节为准；活 PRD 链见 `docs/prd/README.md`（压缩起点 + 0.0.11–0.0.13）。
验收矩阵见 `docs/acceptance.md`。远程 Job 协议见 `docs/engineering/agent-job-protocol.md`。

## Architecture

当前技术栈和边界：

- SwiftUI + SwiftData，最低 iOS 17。
- 可选远程 Agent 实施后，`Server/` 保存独立 TypeScript API/Worker；PostgreSQL 是远程
  Job/Event 事实来源，服务器不成为身体业务数据库。协议见
  `docs/engineering/agent-job-protocol.md`。
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
- PostgreSQL 的表、列、索引、枚举或约束只能通过向前 migration 修改：先运行
  `make db-migrate-create name=<snake_case_name>` 创建新文件，只编辑新 migration，禁止修改或
  删除已经执行的 migration；部署前依次运行 `make db-migrate-status` 与 `make db-migrate`。
- 新增或修改 SwiftData 持久字段、`ModelContainer` 注册模型或 PostgreSQL migration 时，
  必须同步 `docs/engineering/database-schema.md`，并通过数据库结构文档门禁。SwiftData 不使用
  SQL migration 命令。当前只打开 `SomaDataSchema` 当前模型、不带历史 VersionedSchema 计划；
  不兼容变更必须新增 ADR，并明确启动门禁回填或数据重建。
- 长期改变数据模型、Agent 协议、隐私边界、外部同步或分发方式前新增 ADR。
- 远程 Agent 必须通过 `AgentExecutionBackend` 边界接入；View、业务 Tool 和本地
  SwiftData 不感知具体执行位置。

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
- Keychain 使用 ThisDeviceOnly 可访问级别；标准模型未配置 API Key 时在发送前引导配置，
  只有用户明确发送内容才触发远程数据流。
- 新增远程数据流时必须在 PR 中写明发送内容、触发条件、保留策略和失败行为。
- 远程持续执行默认关闭并需一次性明确授权；服务器只保留任务完成所需的最小数据，业务记录
  仍由设备上的确定性 Tool 审查和落地。

## Agent runtime

- 使用 OpenAI-compatible 原生流式 Tool Calling，不要求自定义决策 JSON。
- 每次远程 Attempt 是一条 Trace；同一用户 Turn 可以因重试或恢复拥有多条 Trace。
- 文本增量和 Span 生命周期以 Event 实时更新 UI。
- thinking/reasoning 当前不展示、不持久化，也不用于工具执行。
- 同一 Trace 的重复业务写入必须幂等。
- 工具错误作为 `role: tool` 返回模型；失败 Trace 必须落盘且能解释。
- 已成功的工具写入不因最终回复失败而伪装为未发生。
- 不增加删除、任意代码、云同步或账户工具，除非新 PRD/ADR 明确授权。
- Agent Job、语义 Event 和消费者投影必须持久化；网络投递采用至少一次传输与幂等副作用，
  不能宣称分布式“恰好一次”。
- 本地 Tool 无法在设备挂起时被服务器越权执行；远程工作流必须进入可审查的
  `waitingForDevice`，等待设备执行固定 Tool 并返回结果。

详细协议见 `docs/react-agent.md`、`docs/engineering/agent-job-protocol.md` 和相关 ADR。

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

- 顶层固定为“教练、训练、进展、设置”四个 Tab，并各自保留导航栈；根标题使用紧凑居中样式。
- 主视觉使用黑白：深色纯黑页面与深灰卡，浅色纯白页面与浅灰分组卡；彩色只点缀少量语义图标或状态。
- 浅色语义色适度提高明度与饱和度，抵消纯白背景的灰雾感并保持至少 4.5:1 对比度；暗色语义色不随浅色
  校准改变。
- 语义图标保持清晰实色，不使用阴影、柔光或模糊。
- 颜色分成类别、指标、状态三层：类别色只回答记录类型；指标色回答实际测量含义；状态色只在有确定
  阈值时表达好、需注意或异常。训练不自动等于橙色：频率/连续性用青色，容量/负荷用橙色，恢复用绿色，
  表现用紫色，身体测量用蓝色，生命体征用珊瑚色。黑白只用于导航、文字、选择和主操作，不能无差别
  用于业务 logo、折线、数据点、柱、面积或热力格；坐标轴、网格和分隔线保持中性。同一曲线只有在
  阈值或区间具有确定业务含义时才分段多色，不能为了丰富而使用彩虹色。
- 指标和业务入口使用与含义直接对应的 SF Symbol 或仓库真实素材；不得用一个泛化训练图标覆盖频率、
  容量、恢复、表现、身体和生命体征。
- 未选中 Tab 使用线框图标；选中项可使用填充图标和中性底，不使用彩色品牌导航。
- 页面入口按使用频率排序；低频能力进入设置或高级设置，但反馈保持设置页末端直接可发送。
- 高频上下文可放在输入框附近，低频调试开关不得占用聊天主界面。
- 聊天正文和用户消息使用较小的 Dynamic Type Light 字重；用户消息使用主题灰色气泡，每条消息显示日期与时间。
- AI 正文直接对齐消息区左边界，不增加重复头像或纯装饰图标列。
- 教练输入区只保留加号、文本、语音和发送；快捷 Skill 视觉紧凑但触达区域不少于 44 pt。
- AI 回复只通过本地受控 Markdown 布局呈现标题、段落、分隔线和列表，不能由模型注入任意 UI。
- 详情进入即编辑，修改后出现保存；列表删除遵循系统左滑 destructive action。
- 使用系统文本选择、语音、照片选择器、Charts 和 HealthKit 交互。
- 新交互提供 VoiceOver label，支持 Dynamic Type，并验证空态、错误态和长文本。
- 不展示没有用户意义的内部置信度或 Agent 实现细节。
- 所有肌群受力图使用训练语义色表达主次深浅，不使用黑色着色；计划总览必须保留动作库定义的
  主要/辅助身份，累计组数只能影响强度，不能把辅助肌群重分类为主要肌群。
- 从训练计划进入动作详情时先显示本计划目标；训练历史按最近一次、容量趋势、全部记录分层，
  异构组按连续同值压缩，不显示逐组序号，趋势轴使用真实记录日期。
- 视觉修改至少在 iPhone 尺寸模拟器检查浅色/深色、键盘、滚动和安全区。

## Testing and quality

- 数据真值、去重、容量、热量和 Agent Tool Schema 使用确定性单元测试。
- bug 修复先补能复现问题的测试，再修复。
- 关键 Bug 在 `docs/bugs/` 单独复盘；能自动化的防复发规则必须进入测试或
  `make check`，不能只依赖文档提醒。
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
