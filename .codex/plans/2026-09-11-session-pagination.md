# 进展排序与会话分页

- 月、年训练明细按日期及同日时间倒序；图表、日/周及其他记录维持现有顺序。
- 教练会话抽屉每页查询 14 条，已加载身份排除于后续数据库查询。缓存属于稳定教练根，打开抽屉、切 Session/Tab 不重复加载。
- 新建/修改/删除通过同容器保存通知局部合并；切数据空间丢弃旧缓存。
- 首次为空显示空态，读取失败显示重试并保留已加载页。无持久字段及网络数据流变更。
- 先补排序、分页、同时间戳、增删更新、失败重试与缓存隔离测试；再实现、运行 make check / make verify 与模拟器交互检查。

## 验证结果（2026-09-12）

- `make verify` 通过：833 XCTest、7 Swift Testing；Server 48 通过、1 项按配置跳过。
- `SessionHistoryPaginationUITests` 在 iPhone 17 Pro 浅/深主题通过，14→28 后 Tab/Session 往返保持 `fetches=2`。
- `ProgressHistoryUITests/testMonthAndYearTrainingListStartsAtNewestDay` 在浅/深主题各检查月/年，显示 9月12日→9月9日→9月6日→9月3日。
- 本地截图已目视检查：`build/session-pagination-screenshots/`、`build/progress-order-screenshots/`；未进行真机安装或发布。
