# 每日活动多来源优先级与 COROS 接入调研

- 日期：2026-11-05
- 状态：已转化为 PRD 077 / ADR 0146（产品已锁定 HealthKit-only）
- 修订自：[HealthKit 调研](2026-10-20-healthkit-daily-activity.md)（单通道 HealthKit 合并三项）
- 下游落地：[PRD 077](../archive/0.0.31/prd/077-daily-activity-source-priority.md)、[ADR 0146](../archive/0.0.31/adr/0146-daily-activity-source-priority.md)

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

## 二、COROS 路径结论（2026-11 锁定）

调研阶段对比过三条路径：

| 路径 | 审批 | 能力摘要 | 对本产品 |
| --- | --- | --- | --- |
| COROS App → Apple 健康 → HealthKit 分来源 | 无 | 步数、步跑距离等写入健康库；可按 `HKSource` 摘 COROS | **采纳**：用户只授权 Apple 健康；Soma 按设置读 COROS 整包或跟系统汇总 |
| Build on COROS MCP | 自助 OAuth | `queryDailyHealthData` 等；需 HTTPS 回调；距离字段文档不全 | **本需求不做**（默认与可选皆不做） |
| Partner API | 公司申请 | 日汇总 / webhook 等 | **不做** |

补充事实（影响新鲜度预期，不改变通道选择）：

- 表日常链路是手表 → 手机 COROS App（蓝牙）→ 云 / 健康库；MCP 同样依赖 App 先上云，绕不过「先开/后台同步 COROS」。
- 官方与 Reddit 长期反馈：强制杀 COROS、关后台刷新会导致不同步；Apple Watch→HealthKit 无同类「必须开厂商 App」问题。
- 没有可靠的「放置 iPhone 保证 COROS 永久常驻」方案；实用组合是不杀进程 + 后台刷新 + Auto Sync + 习惯/快捷指令偶发打开。

**产品锁定：** 日活动只走 HealthKit。设置「日活动数据源」概念上 = COROS（HealthKit 来源过滤整包）/ Apple（跟系统汇总）/ 步数更大（整包比步数）。**默认 Apple**。COROS 选项仅当健康库已有 COROS 来源日活动样本时显示，否则隐藏。不做 MCP OAuth UI。

## 三、优先级与整包一致性

用户规则：步数、距离、活动消耗必须来自**同一获胜来源快照**。禁止「COROS 步数 + Apple 距离/热量」混拼。

策略枚举（设置可改；**默认 Apple**）：

1. **Apple**（始终可选）：HealthKit 系统合并 / 内部择优；Soma 不重选。
2. **COROS**（仅健康库已有 COROS 来源样本时显示）：HealthKit 中来源为 COROS 的整包；不完整则回退 Apple 汇总，图标如实反映。无样本时不展示该选项。
3. **步数更大**（始终可选）：在可用整包间比较步数；平手按稳定次序打破平局；仍整包采用。无 COROS 时候选通常只剩 Apple。

比较键只用步数；获胜后三项与来源图标一并采用。缺项保持 `nil`，不向落选快照借数。

UI：可见选项前分别加对应 logo——Apple 健康 logo、COROS logo（选项可见时）、非品牌「更大/择优」图标（gauge / 向上箭头等）。

## 四、信息架构

- 日常活动退出训练记录主列表与「按日分享」聚合。
- 单独「每日步数 / 日常活动」列表：日期、步数、距离、卡路里、来源图标（COROS / Apple 健康等）。
- 详情仍可审查三项；来源图标是用户可见元数据，不再隐藏。

## 五、隐私与范围

- 仍 local-first：日汇总不进模型上下文、备份导出、Server、Widget。
- **无** COROS Token / OAuth / 新远程数据流。
- 不写回 HealthKit；不读静息能量、心率、睡眠（除非未来独立 PRD）。
- 不把任何 MCP 工具面暴露给教练 Agent。

## 六、验收与 Spike

确定性：默认 Apple、COROS 选项有样才显示/无样隐藏、曾选 COROS 后样本消失回退、三种策略、COROS 缺包回退、平局次序、缺项不混拼、分享过滤、列表隔离、来源图标、设置项 icon、旧 `appleHealth:daily:` 记录迁移或识别兼容、无 COROS OAuth UI。

真机 Spike（不入库真实数值）：HealthKit 分来源统计能否稳定识别 COROS 三项并与系统汇总对照。不要求 MCP discovery / 授权 Spike。
