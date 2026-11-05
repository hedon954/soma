# ADR 0146：日常活动多来源整包择优与列表边界

- 状态：提议
- 日期：2026-11-05
- 维护者：Soma maintainers
- 部分替代：[ADR 0144](0144-healthkit-daily-activity.md)（仅系统合并 HealthKit、externalSource 固定 appleHealth、日常活动混入训练列表且分享不排除、界面不展示来源）
- 上游依据：[PRD 077](../prd/077-daily-activity-source-priority.md)、[多来源调研](../research/2026-11-05-daily-activity-source-priority.md)
- 后续替代：暂无

## 背景

ADR 0144 通过 HealthKit 三项日统计覆盖为一条运动记录，并用系统 `cumulativeSum` 合并多写入者。COROS 依赖健康同步时延迟与来源优先级不可控。用户需要可配置的来源优先级，且步数/距离/卡路里必须同源；同时日常活动不应出现在训练列表与分享海报中。

已有 `DailyActivityReading` 协议，具备替换实现的接缝，但落盘身份与 UI 仍写死 Apple 健康，且分享聚合未过滤 `isDailyActivity`。

## 决策

### 读取与择优

- 保留并强化 `DailyActivityReading`：每个连接来源（HealthKit、未来的 COROS MCP Reader 等）产出**按自然日的候选快照**（三项 + 来源归因），而不是先合并再展示。
- HealthKit 实现除系统合并外，对已授权窗口使用按 `HKSource` 的分项统计，以便在健康库内识别 COROS 与 Apple 系样本；不再把 `separateBySource` 仅当作名称装饰。
- 新增本机优先级策略（设置持久化，排除备份策略与连接状态文件一致评估）：`preferCoros` / `preferAppleHealth` / `maxSteps`。
- 同步协调器在写入前对每个自然日做**整包择优**：先按策略选出至多一个快照，再交给 `DailyActivityRecordStore` 覆盖。落选快照的任何指标不得补进获胜快照。

### 身份与模型

- 每个自然日仍一条日常活动记录；稳定 `externalID` 保持 `daily:yyyy-MM-dd`。
- `externalSource` 改为记录**获胜来源**稳定标识（如 `appleHealth`、`coros`），不再永远写死 `appleHealth`。
- `isDailyActivity` 改为以 `externalID` 的 `daily:` 前缀（或等价专用标记）识别，避免新来源无法识别旧逻辑；迁移时兼容旧 `appleHealth` 记录。
- `dailyActivityData` 必须能还原三项数值与用于图标的来源种类；不在主训练详情堆叠原始多来源表，列表图标足够。

### COROS 直连

- 个人版优先自助 COROS MCP + OAuth（用户授权、设备轮询），封装为另一个 `DailyActivityReading` 实现；Token 进 Keychain。
- 不在本 ADR 引入 Partner API、Server 代持 COROS 令牌或 webhook。
- MCP 日汇总若缺距离：该项为 `nil`，不得用 HealthKit 其他来源距离拼装；可在同属 COROS 的 HealthKit 分项距离可读时写入同一 COROS 快照，并在归因中如实记录。

### 列表与分享

- 训练历史、进展「训练」投影、教练上下文继续排除日常活动（已有多处 filter 的保持，并补齐仍混入的列表）。
- 新增独立日常活动历史入口（设置旁或进展次级入口，实现时选最小改动路径），行内展示来源图标。
- `WorkoutSharePosterBuilder.makeModel(forDay:)` 及任何按日聚合分享在投影前排除 `isDailyActivity`；课程/会话分享本就不含日常活动则加回归锁。

## 未选择的方案

- **继续只靠系统合并 + 文案让用户改健康 App 优先级**：无法解决延迟与混拼，也不满足可选 COROS 优先。
- **按指标分别取最大再组合**：用户明确禁止。
- **立即申请 Partner API**：个人本地优先产品过重；MCP 可先验证字段与授权。
- **把日常活动做成独立 SwiftData 模型并迁移全部能量链路**：收益不足以覆盖与 ADR 0144/0145 投影的改动面；先保留 `WorkoutEntry` 日记录并收紧边界。
- **为每个来源每天存多条 WorkoutEntry**：破坏「一日一条」与能量投影假设。

## 结果

### 正向影响

- 协议接缝真正用于多实现；用户可控来源策略；分享与训练列表不再被步数污染；来源可审查。

### 成本与限制

- HealthKit 分来源查询与 COROS OAuth/轮询增加复杂度与失败面。
- MCP 工具契约若变更需适配；距离字段可能阶段性缺失。
- 旧记录识别与备份过滤规则需同步更新（凡写死 `externalSource == appleHealth` 的过滤改为日常活动识别）。

## 验证

- 单元测试：三种策略、平局、缺项不混拼、分享过滤、列表隔离、旧记录兼容。
- `make check` / `make verify`；文档生命周期双向链接门禁。
- 真机 Spike：分来源统计、COROS 授权与 `queryDailyHealthData` 字段、延迟对照（不入库真实数值）。

## 参考

- [PRD 075](../prd/075-healthkit-daily-activity.md)、[ADR 0144](0144-healthkit-daily-activity.md)
- `Soma/Services/Health/HealthKitDailyActivityReader.swift`、`DailyActivitySyncCoordinator.swift`、`DailyActivityRecordStore.swift`
- `Soma/Views/WorkoutSharePosterBuilder.swift`、`HealthActivitySettingsView.swift`
- [COROS MCP](https://support.coros.com/hc/en-us/articles/53181619102996-Build-on-COROS-MCP)、[Partner API](https://support.coros.com/hc/en-us/articles/53181766856724-Partner-API-Access)
