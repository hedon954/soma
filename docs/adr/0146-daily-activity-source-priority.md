# ADR 0146：日常活动多来源整包择优与列表边界

- 状态：提议
- 日期：2026-11-05
- 维护者：Soma maintainers
- 部分替代：[ADR 0144](0144-healthkit-daily-activity.md)（仅系统合并 HealthKit、externalSource 固定 appleHealth、日常活动混入训练列表且分享不排除、界面不展示来源）、[工程契约](../../CLAUDE.md)（外部导入与可替换边界：日活动多来源择优仍经 HealthKit）
- 上游依据：[PRD 077](../prd/077-daily-activity-source-priority.md)、[多来源调研](../research/2026-11-05-daily-activity-source-priority.md)
- 后续替代：暂无

## 背景

ADR 0144 通过 HealthKit 三项日统计覆盖为一条运动记录，并用系统 `cumulativeSum` 合并多写入者。COROS 写入健康库后可按 `HKSource` 分项统计，但系统合并不一定优先 COROS；用户需要可配置的「日活动数据源」，且步数/距离/卡路里必须同源。日常活动不应出现在训练列表与分享海报中。

已有 `DailyActivityReading` 协议，具备替换实现的接缝，但落盘身份与 UI 仍写死 Apple 健康，且分享聚合未过滤 `isDailyActivity`。调研与产品讨论后锁定：**本需求仅 HealthKit**；COROS MCP / OAuth 不做默认也不做可选。

## 决策

### 读取与择优（HealthKit-only）

- 保留并强化 `DailyActivityReading`：由 HealthKit 实现产出**按自然日的候选快照**（三项 + 来源归因），而不是先合并再展示。
- HealthKit 实现除系统合并外，对已授权窗口使用按 `HKSource` / bundle 的分项统计，以便识别 COROS 与 Apple 系样本；不再把 `separateBySource` 仅当作名称装饰。
- **不**新增 COROS MCP Reader、OAuth、Keychain 令牌或远程轮询。用户只授权 Apple 健康一次。
- 设置持久化「日活动数据源」枚举（排除备份策略与连接状态文件一致评估）：
  - `apple`：采用 Apple 健康系统汇总 / 内部择优（`cumulativeSum` 或等价系统总量）；Soma 不重选来源。
  - `coros`：取 HealthKit 中来源为 COROS 的样本组成整包（步数+距离+卡路里）。
  - `maxSteps`：在可用整包候选之间比较步数，取更大者；仍整包采用。
- **产品默认：`apple`**（Hedon 锁定）。用户可在选项可见时改为 `coros` 或 `maxSteps`。
- **COROS 选项可见性**：设置 UI 仅在健康库已能识别 COROS 日活动来源时展示 `coros` 行。判定：对已授权的日活动相关类型（至少步数；实现可扩展到距离/活动能量）在合理回看窗口（与同步窗口一致或 ADR 实现选定的固定天数，如最近 30 天）内，`separateBySource` / 等价分来源查询能得到至少一个 COROS `HKSource`（bundle / 名称匹配规则与整包识别相同）。无匹配则隐藏 COROS 选项；`apple` 与 `maxSteps` 在已授权后始终展示。
- **持久化与隐藏交互**：若持久化值为 `coros`，但当前判定 COROS 不可见（样本消失或尚未写入），读取策略时**按 `apple` 行为**，并将持久化纠正为 `apple`（避免设置页与同步策略长期不一致）。用户再次出现 COROS 样本后，不自动切回 `coros`，需用户手动选择。
- 同步协调器在写入前对每个自然日做**整包择优**：先按策略选出至多一个快照，再交给 `DailyActivityRecordStore` 覆盖。落选快照的任何指标不得补进获胜快照。

### COROS 缺包与回退

- 「完整 COROS 整包」：当日能从 COROS 来源读到可用于展示的步数，且距离、卡路里按同来源同日样本组装（缺项保持 `nil`，不向 Apple 借数填 COROS 包）。
- 策略为 `coros` 但当日无可用 COROS 整包（无 COROS 样本、或无法形成至少含步数的候选）时：**回退到 Apple 健康汇总快照**；`externalSource` / 图标反映实际采用的来源（如 `appleHealth`），不得假装仍是 COROS。
- 策略为 `maxSteps` 时，候选集合至少包含：可用的 COROS 整包（若有）、Apple 汇总整包（若有）；只比较这些整包的步数；平手按稳定次序（例如 `coros` > `apple`）打破平局。
- 策略为 `apple` 时不做来源重选，直接系统汇总。

### 身份与模型

- 每个自然日仍一条日常活动记录；稳定 `externalID` 保持 `daily:yyyy-MM-dd`。
- `externalSource` 改为记录**获胜来源**稳定标识（如 `appleHealth`、`coros`），不再永远写死 `appleHealth`。
- `isDailyActivity` 改为以 `externalID` 的 `daily:` 前缀（或等价专用标记）识别，避免新来源无法识别旧逻辑；迁移时兼容旧 `appleHealth` 记录。
- `dailyActivityData` 必须能还原三项数值与用于图标的来源种类；不在主训练详情堆叠原始多来源表，列表图标足够。

### 设置 UI（icon）

- 「日活动数据源」每个**当前可见**选项前必须带对应视觉标识：Apple 健康（或 Apple）logo；COROS logo（仅选项可见时）；步数更大用非品牌的 gauge / 向上箭头类图标。
- 无 COROS 样本时设置页只显示 Apple 与步数更大两行，不留空位或禁用态的 COROS 行。
- 独立日常活动列表行内展示获胜来源图标（与设置选项同一套来源视觉语言）。

### 列表与分享

- 训练历史、进展「训练」投影、教练上下文继续排除日常活动（已有多处 filter 的保持，并补齐仍混入的列表）。
- 新增独立日常活动历史入口（设置旁或进展次级入口，实现时选最小改动路径），行内展示来源图标。
- `WorkoutSharePosterBuilder.makeModel(forDay:)` 及任何按日聚合分享在投影前排除 `isDailyActivity`；课程/会话分享本就不含日常活动则加回归锁。

### 同步新鲜度（产品预期，非技术保证）

- Soma 不要求用户为查看日活动专门打开 COROS App；也不承诺打开 Soma 即实时。
- 今日数据可能因「表 → COROS App → 健康库」链路略旧；昨天及以前通常已在健康库中。实现可展示最后同步/读取时间（可选），但不得强制跳转 COROS。

## 未选择的方案

- **继续只靠系统合并 + 文案让用户改健康 App 优先级**：无法满足可选 COROS 优先与来源可审查。
- **按指标分别取最大再组合**：用户明确禁止。
- **COROS MCP / OAuth 作为默认或可选直连**：用户已确认健康库可按来源摘出 COROS；MCP 仍依赖 App 先上云，且增加 OAuth / HTTPS 回调与距离字段不确定性；本需求明确不做。
- **申请 Partner API**：个人本地优先产品过重，且不解决 App 同步。
- **把日常活动做成独立 SwiftData 模型并迁移全部能量链路**：收益不足以覆盖与 ADR 0144/0145 投影的改动面；先保留 `WorkoutEntry` 日记录并收紧边界。
- **为每个来源每天存多条 WorkoutEntry**：破坏「一日一条」与能量投影假设。

## 结果

### 正向影响

- 用户可控数据源且零额外厂商授权；整包一致；分享与训练列表不再被步数污染；来源可审查。

### 成本与限制

- HealthKit 分来源查询增加复杂度；仍受 COROS→健康库同步延迟约束。
- 旧记录识别与备份过滤规则需同步更新（凡写死 `externalSource == appleHealth` 的过滤改为日常活动识别）。

## 验证

- 单元测试：默认 `apple`、COROS 选项可见/隐藏、曾选 `coros` 后样本消失回退并纠正持久化、三种策略、COROS 缺包回退、平局、缺项不混拼、分享过滤、列表隔离、旧记录兼容。
- `make check` / `make verify`；文档生命周期双向链接门禁。
- 真机 Spike：分来源统计能否稳定识别 COROS 三项；与系统汇总对照（不入库真实数值）。不要求 COROS MCP Spike。

## 参考

- [PRD 075](../prd/075-healthkit-daily-activity.md)、[ADR 0144](0144-healthkit-daily-activity.md)
- `Soma/Services/Health/HealthKitDailyActivityReader.swift`、`DailyActivitySyncCoordinator.swift`、`DailyActivityRecordStore.swift`
- `Soma/Views/WorkoutSharePosterBuilder.swift`、`HealthActivitySettingsView.swift`
