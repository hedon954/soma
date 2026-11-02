# HealthKit 每日运动记录实现计划

- 日期：2026-10-21
- 依据：[PRD 075](../../docs/prd/075-healthkit-daily-activity.md)、[ADR 0144](../../docs/adr/0144-healthkit-daily-activity.md)
- 范围：每日步数、距离、活动消耗写为一条运动记录，同日覆盖，进入既有统计；不增加独立卡或来源/时间元数据 UI。

- [x] 固定三项只读查询、真实 source、自然日窗口及根层前台 owner。
- [x] WorkoutEntry 新增可空 dailyActivityData；唯一日身份覆盖，部分失败不覆盖，空结果清除。
- [x] 复用记录列表和详情，删除独立卡片；活动能量替换活动系数和训练增量，进入既有统计。
- [x] 个人库保护/备份排除，应用备份/导出及模型上下文过滤；内部回滚保留字段。
- [x] 记录覆盖、来源、nil/0、去重、能量缺口/推荐目标、旧数据兼容及隔离测试。
- [x] 浅深主题、大字号、小屏与 iPad 虚构记录界面。
- [x] make format / make check / make verify 与重新安装到 iPhone 17 Pro Max。
- [ ] 真机授权、COROS 和系统统计/删除/锁屏行为验收。

2026-10-21：完整 make verify 通过（899 XCTest、8 Swift Testing；Server 60 通过、1 跳过）。
DailyActivityUITests 在 iPhone 17 Pro、iPhone 16e、iPad Pro 11-inch 各 2 项通过，覆盖浅深主题、
Accessibility XXXL、记录列表、三指标详情与设置；截图仅为虚构数据，位于 build/health-record-ui-*-final。
保留同一历史查询 owner，避免保存记录触发快照刷新后反复重启查询；全量训练列表按已加载条数刷新，
可呈现同步新增与删除。清空/恢复前先停止健康读取，迟到事件不能重新写入数据。
已覆盖安装 Soma 0.0.27（31）Debug 至 iPhone 17 Pro Max，签名 HealthKit entitlement 和安装输入指纹均已核对。
未在设备上打开应用或读取真实健康数据，权限与 COROS 对照仍待手工验收。
