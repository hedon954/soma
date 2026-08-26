# ADR 0099：行为保持现代化与三版本活文档窗口

- 状态：已采纳
- 日期：2026-08-25
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md) 的仓库布局与活文档窗口规则
- 后续替代：暂无
- 上游依据：[PRD 044](../prd/044-behavior-preserving-modernization.md)

## 背景

0.0.12 的产品边界已经稳定，但实现与文档的物理布局仍按历史增量堆在超长文件和完整活目录中。
Agent 默认会把全部 PRD/ADR 读进上下文，既增加噪声，也让真正有效的最近版本决策被淹没。
同时，对话写入、带练相机和测试夹具的文件边界已经超过 500 行软上限，继续在原文件修改会
提高行为回归风险。需要一次不改变对外契约的布局决策。

## 决策

1. **行为保持**：本轮只允许删除确认未引用的代码、按领域拆分文件、收敛测试假存储契约、
   删除无逻辑价值的单元测试。禁止改 Tool Schema、Job/Event、SwiftData 字段、LLM 契约、
   HTTP API 或热路径性能特征。
2. **对话写入**：`ConversationProcessingService` 是编排器；`ConversationTurnPersistence`
   是 Job/Event/消息持久化门面。按本地域拆文件，不改变幂等、FIFO 暂存与 Tool 语义。
3. **带练与相机**：状态机与 `AVCapture` 生命周期分文件；预览宿主所有权、朝向与 activation
   期限仍遵守既有 bug 文档。
4. **组合根**：`SomaApp` 只装配依赖；教练气泡、输入与队列 UI 从 `CoachView` 抽出，不改服务调用。
5. **Server**：生产只使用 Postgres store；内存实现只服务测试，并共享同一 `SomaStore` 契约。
6. **活文档链按营销版本，不按文件日期**：阅读顺序是压缩起点 → 最近 3 个
   `MARKETING_VERSION`（采纳时为 0.0.13 / 0.0.12 / 0.0.11；当前窗口见 README）。压缩起点
   （`docs/prd/000-origin-through-0.0.11.md`、`docs/adr/0000-origin-through-0.0.11.md`）
   是滑出窗口内容的滚动收口：只保留仍有效的最终要求与决策，不是旧 PRD/ADR 清单或过渡史。
   窗口最旧活文档的修订自 / 部分替代指向压缩起点；起点没有更早的活前驱。
7. **发布时合并压缩起点，不要只搬家**：每次新 App 发布，把滑出版本原文 `git mv` 到
   `docs/archive/<version>/`，并把「现有压缩起点 + 该版本仍有效的最终状态」合并为新起点。
   这与 Agent 消息滚动压缩相同。归档不 gitignore。
8. **Agent 忽略归档，终端不忽略**：
   - Cursor：根 `.cursorignore` 写入 `docs/archive/`（gitignore 语法）。官方 ignore 文件会
     阻止 Agent / Tab / `@`，**不会**阻止终端或 MCP。
   - Claude Code：`.claude/settings.json` 的 `permissions.deny` 包含 `Read(./docs/archive/**)`；
     Read deny 同时阻止对该路径的 Edit/Write。不依赖非官方 `.claudeignore`。
   - Codex：不新增 `.codexignore`（`openai/codex#24993` 仍开放）。`CLAUDE.md` / `AGENTS.md`
     明确：默认不要读取 `docs/archive/`，除非维护者要求历史。
9. **生命周期门禁验证活文档互链**。归档原文是考古，不要求与活文档互链；不要为通过门禁而
   改写归档决策正文。
10. **按能力目录拆分实现，不引入 DDD 应用层**：
    - ReAct 循环本体在 `AIService+ReActLoop`，重试策略在 `AgentStepRetryPolicy`，原生
      `tool_calls` 流式累积在 `AgentStreamingToolCall` / `AgentStreamWorker`，滚动压缩在
      `ConversationCompactionMiddleware`。`ReActAgent` 只保留可配置上限与错误门面。
    - SwiftData 业务类型按实体文件拆分；不增加平行 DTO。
    - `Soma/Services/` 分为 `Conversation`、`Training`、`Media`、`Settings`。后续改动按能力
      目录查找，不把 100+ 文件摊回单层。
    - 禁止引入 application / use-case / repository / entity 分层或新的 `AppServices`
      上帝对象。相同的 `sameToolRequest` 比较只允许抽成共享函数，不另建存储架构。

## 未选择的方案

- 不把活窗口做成「只把旧文件搬进 archive、Agent 失去起点」。压缩起点必须是仍有效要求与
  决策的滚动收口。
- 不按文件日期归档：0.0.9 / 0.0.10 / 0.0.11 曾在同一公历日发布，日期排序会把活窗口切错。
- 不把归档加入 gitignore：未压缩原文必须留在仓库，供人类考古。
- 不把本次当作 schema 或 Swift 6 迁移：那会改变启动、数据或工具链契约。
- 不引入新的全局 `AppServices` 工厂：组合根已经是 `SomaApp`。
- 不引入 DDD application / use-case / repository 层：本次只移动和拆分现有类型。
- 不为 Codex 发明 `.codexignore`：上游忽略文件能力尚未稳定。

## 结果

### 正向影响

- Agent 默认先读压缩起点，再读三个营销版本的增量。
- 滑出窗口时把该版本折叠进起点，活链长度保持稳定。
- 超长写入路径、带练相机、组合根、ReAct 循环、SwiftData 实体和 Services 按能力目录拆分，
  后续改动的审查面更小。
- 生产 Store 与测试假存储共用契约，HTTP 面保持不变。

### 成本与限制

- 查阅滑出最近三版窗口的原始决策需要显式打开归档。
- Linux/cloud 环境不能运行 Simulator，完整 `make check` / `make verify` 仍依赖 Mac。
- `private(set)` 等模块内可见性可能为跨文件 extension 放宽为 internal，但不构成公开 API。

## 验证

- `make server-check`、`make server-test`、`make perf-check`（在可安装 Ruby/Node 的环境）。
- `scripts/check-document-lifecycle-links.rb` 与 `scripts/validate-repository.sh`。
- Mac 上补跑 `make check` 与 `make verify`，并做教练发送、带练预览/录像的点选回归。

## 参考

- [PRD 044](../prd/044-behavior-preserving-modernization.md)
- [Cursor ignore 文件](https://cursor.com/docs/reference/ignore-file)
- [Claude Code permissions](https://code.claude.com/docs/en/permissions)
- [Codex ignore issue](https://github.com/openai/codex/issues/24993)
