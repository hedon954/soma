# 每日活动多来源优先级与 COROS 接入调研

- 日期：2026-11-05
- 状态：已转化为 PRD 077 / ADR 0146
- 修订自：[HealthKit 调研](2026-10-20-healthkit-daily-activity.md)（单通道 HealthKit 合并三项）
- 下游落地：[PRD 077](../prd/077-daily-activity-source-priority.md)、[ADR 0146](../adr/0146-daily-activity-source-priority.md)

## 一、现状（代码事实）

| 层 | 现状 |
| --- | --- |
| 读取协议 | `DailyActivityReading`（`HealthKitDailyActivityReader.swift`）已抽象授权与窗口更新流 |
| 唯一实现 | `HealthKitDailyActivityReader`：三项用 `cumulativeSum` 取系统合并值；`separateBySource` 只保留来源名称元数据，不加总来源分项 |
| 同步 | `DailyActivitySyncCoordinator` 注入 `any DailyActivityReading`，默认 HealthKit |
| 落盘 | `DailyActivityRecordStore` 每天一条 `WorkoutEntry`，`externalSource` 固定 `"appleHealth"`，`externalID` 为 `daily:yyyy-MM-dd` |
| 识别 | `WorkoutEntry.isDailyActivity`：`appleHealth` + `daily:` 前缀 |
| 列表 | 训练历史 / 进展活动列表混入「日常活动」行（`HistoryViews`、`ProgressHomeComponents`） |
| 分享 | `WorkoutSharePosterBuilder.makeModel(forDay:)` 拉取当日全部 `WorkoutEntry`，**未排除**日常活动 |
| 设置 | `HealthActivitySettingsView` 只连接 Apple 健康；文案引导用户先让 COROS 写入健康库 |

产品意图（PRD 075）：COROS 经 Apple 健康间接进入；页面不展示来源列表。真机上用户观察到：COROS → Apple 健康有延迟，且健康库不一定优先采用 COROS 的步数与卡路里。系统合并值无法满足「优先 COROS」或「步数更大者整包取用」。

## 二、COROS 接入路径（2026-11 公开资料）

官方帮助中心与第三方对照（不编造未公开的请求体）：

| 路径 | 审批 | 能力摘要 | 对本产品 |
| --- | --- | --- | --- |
| COROS App → Apple 健康 → HealthKit | 无 | 步数、步跑距离等写入健康库；活动能量需真机确认 | **现有路径**；延迟与来源优先级不可控 |
| Build on COROS MCP | 自助，无审批 | OAuth 2.0 + `https://mcp.coros.com/mcp`；工具含 `queryDailyHealthData`（步数、卡路里等日汇总）、运动记录与 FIT | 适合个人版单用户直连；无 webhook，需轮询；距离字段需对照工具返回再定 |
| Partner API | 公司平台申请 | `getDailyData`、`getWorkoutRecords`、webhook 等 | 多用户与推送更强；个人本地优先产品短期成本过高 |

公开说明摘要：

- MCP：用户为本机授权即可；访问仅限授权用户；无 GPX / 双向活动同步 / webhook（见 [Build on COROS MCP](https://support.coros.com/hc/en-us/articles/53181619102996-Build-on-COROS-MCP)）。
- Partner：需注册公司与技术联系人，发往 `api@coros.com`（见 [Partner API Access](https://support.coros.com/hc/en-us/articles/53181766856724-Partner-API-Access)）。
- 第三方对照：MCP 可用 Dynamic Client Registration + PKCE；区域主机曾分 `mcpus` / `mcpeu` / `mcpcn`，官方亦提到统一 `mcp.coros.com`（实现前用 discovery 实测，不以二手文章为准）。
- GitHub：`coroslab/COROS-MCP` 为官方 MCP / Agent 文档入口。

**结论：** 第一阶段不申请 Partner。优先（1）在 HealthKit 上按来源取分项统计并做整包择优；（2）可选增加实现 `DailyActivityReading` 的 COROS MCP Reader，用 OAuth 直读日汇总，缓解健康同步延迟。距离若 MCP 日汇总缺失，不得用另一来源的距离拼装；该项保持空，或仅在同来源 HealthKit COROS 样本可读时补齐并标明来源。

## 三、优先级与整包一致性

用户规则：步数、距离、活动消耗必须来自**同一获胜来源快照**。禁止「COROS 步数 + Apple 距离/热量」混拼。

建议策略枚举（设置可改，默认需产品确认；提议默认「步数更大者」）：

1. **优先 COROS**：有完整或至少含步数的 COROS 快照则用它，否则回退下一可用来源。
2. **优先 Apple 健康**：用 HealthKit 系统合并或 Apple 系来源快照。
3. **步数更大者**：在可用快照间比较步数；平手时按稳定次序（例如已连接优先列表）打破平局。

比较键只用步数；获胜后三项与来源图标一并采用。缺项保持 `nil`，不向落选快照借数。

## 四、信息架构

- 日常活动退出训练记录主列表与「按日分享」聚合。
- 单独「每日步数 / 日常活动」列表：日期、步数、距离、卡路里、来源图标（COROS / Apple 健康 / 未来来源）。
- 详情仍可审查三项；来源图标是用户可见元数据，不再隐藏。

## 五、隐私与范围

- 仍 local-first：Token 进 Keychain（ThisDeviceOnly）；日汇总不进模型上下文、备份导出、Server、Widget。
- COROS OAuth 是新的远程数据流：PR 必须写明发送内容（授权码换票）、触发条件、刷新失败与撤销。
- 不写回 HealthKit；不读静息能量、心率、睡眠（除非未来独立 PRD）。
- 不把 MCP 工具面暴露给教练 Agent 作为任意工具。

## 六、验收与 Spike

确定性：整包择优、平局次序、缺项不混拼、分享过滤、列表隔离、来源图标、旧 `appleHealth:daily:` 记录迁移或识别兼容。

真机 Spike（不入库真实数值）：HealthKit 分来源统计；COROS MCP discovery / 授权 / `queryDailyHealthData` 字段是否含距离；与健康库延迟对照。
