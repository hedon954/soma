# PRD 044：行为保持的工程现代化

- 状态：已采纳，已实施于 0.0.13；不改变用户可见行为
- 日期：2026-08-25
- 修订自：[PRD 043](043-configurable-react-runtime-timeout.md) 作为 0.0.12 活产品窗口头部
- 后续修订：暂无
- 上游依据：维护者批准的行为保持现代化计划
- 下游落地：[ADR 0099](../adr/0099-behavior-preserving-modernization-and-three-version-docs.md)
- 关联决策：[ADR 0098](../adr/0098-user-configurable-react-active-runtime-timeout.md)

## 背景

Soma 在 0.0.12 已经具备完整产品闭环，但代码与文档按多年增量堆叠：对话写入路径、带练相机、
组合根、测试夹具和全部历史 PRD/ADR 都集中在少数超长文件或活目录里。继续在原文件上叠加会
放大审查成本，却不能改变用户结果。需要一次**行为保持**的现代化：拆分、删除真正未引用代码、
把滑出窗口的文档**折叠成压缩起点**（而不是只搬家），并且明确禁止协议/模式迁移。

## 用户结果

用户可见行为与 0.0.12 发布基线一致，源码版本前移到 0.0.13：

1. 教练发送、暂存补偿、Job/Event 投影、Tool 执行与幂等语义不变。
2. 带练状态机、预览宿主、朝向锁定与相机 activation 期限不变。
3. 设置、记录审查、工具列表与可选 Server HTTP API 不变。
4. 营销版本为 `0.0.13`；本 PRD 描述的工程整理构成该源码版本的全部变化。

开发者结果：活 PRD/ADR 是压缩起点加上最近 3 个营销版本；滑出窗口时把该版本合并进起点。
归档原文可查但默认不进入 Agent 上下文。

## 产品规则

- 不改变公开 Tool Schema、Job/Event 协议、SwiftData 持久字段、LLM Provider 契约。
- 不增加主线程工作，不在热路径增加 I/O；`make perf-check` 规则保持。
- 删除的代码必须确认零调用；不确定则保留并记为后续项。
- 对话写入拆成编排器与持久化门面，但不改变 FIFO 暂存、幂等键与 Tool 执行顺序。
- 带练与相机按状态机 / AVCapture 生命周期拆文件，保留既有 bug 文档约束。
- App 组合根只装配依赖；教练气泡/输入/队列 UI 拆出后仍调用同一服务。
- 生产 Server 继续只用 Postgres；测试假存储实现同一契约，不改 HTTP。
- 单元测试按领域拆分后断言含义不变；只删除无逻辑价值的字符串镜像断言。
- 若一项改动等于 schema/API/框架迁移，跳过并列入后续。
- `ReActAgent.swift` 只保留循环门面（步骤上限、超时、错误）；循环本体、无可见增量重试、
  原生 `tool_calls` 流式累积、会话滚动压缩各有唯一所有者文件。不改变重试次数、截止期限、
  暂存或 Tool 执行顺序。
- `Models.swift` 按真实实体拆到 `Meal` / `WorkoutEntry` / `Gym` / `BodyEntry` /
  `CoachMessage` / `AgentTrace` 等文件；不增加平行 DTO 层。
- `Soma/Services/` 按能力目录分组：`Conversation`、`Training`、`Media`、`Settings`。
  对话改动应命中 `Conversation/`，训练改动应命中 `Training/`。禁止引入 DDD 的
  application / use-case / repository / entity 层，也禁止新的 `AppServices` 上帝对象。

## 数据与隐私

- 不新增或改变业务数据、媒体、凭据或远程发送内容。
- 文档归档留在 Git，不进入 gitignore；Agent 忽略规则不得用于隐藏密钥或身体数据。
- 测试与文档继续只使用虚构数据。

## 明确不在范围

- Swift 6 language mode、SwiftData VersionedSchema、PostgreSQL schema 变更。
- 新的 `AppServices` 工厂类型、DDD application / use-case / repository 层、Tool 列表或 HTTP 路由重写。
- 重写已归档 PRD/ADR 决策正文。
- 在 Linux/cloud VM 上宣称已完成模拟器或真机验收。

## 验收

- 活 `docs/prd/` 与 `docs/adr/` 含压缩起点（000 / 0000）以及 0.0.11–0.0.13 窗口文档。
- 压缩起点只写仍有效的最终要求与决策，不是旧文件清单；0.0.11 文档的修订自 / 部分替代指向起点。
- 窗口规则是「滑出时合并进起点」，不是只把文件搬进 archive。
- `docs/archive/<version>/` 含 0.0.10 及更早未压缩原文；根 `.cursorignore` 忽略该目录；
  `.claude/settings.json` deny `Read(./docs/archive/**)`；`CLAUDE.md` 要求 Codex 默认不读归档。
- 公开工具列表与 Server HTTP API 与现代化前一致。
- `Soma/Services/ReActAgent.swift` 与 `Soma/Models/Models.swift` 不再作为上帝文件存在。
- `Soma/Services/` 按 `Conversation` / `Training` / `Media` / `Settings` 分组。
- Linux 上可运行的 `make server-check`、`make server-test`、`make perf-check` 通过；
  `make check` / `make verify` 仍需 macOS 与 Simulator。
