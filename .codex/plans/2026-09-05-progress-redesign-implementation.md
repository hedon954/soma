# 进展页改造 TODO

- 状态：代码、本地门禁、提交推送与双机安装完成；真实 HealthKit 验收继续跟踪
- 用户目标：能查看任意一天，以及周、月、年的饮食、能量、训练、身体趋势
- 上游依据：[PRD 053](../../docs/prd/053-adaptive-energy-estimation-and-progress.md)、[PRD 054](../../docs/prd/054-progress-history-and-periods.md)、[ADR 0114](../../docs/adr/0114-progress-periods-and-adaptive-energy.md)
- 设计：[四个周期设计稿](../../docs/assets/ui/2026-09-05/progress-refinement/README.md)
- 总跟踪：[BUG-20](2026-09-02-coach-training-critical-bugfixes.md)

## 页面与交互

- [x] P01 日／周／月／年共用日期状态；自然周从周一开始，支持闰年、跨年、夏令时。
- [x] P02 上一周期／下一周期、日历选日、回到当前周期；未来日期不可选，超出当前周期的下一步置灰；切 Tab、返回详情保持选择与位置。
- [x] P03 首页固定为饮食与能量主图、训练卡、身体卡；保留资源入口的可达路径。
- [x] P04 日页：摄入、全天预估消耗、差值、三大营养素、饮食／训练／身体记录。
- [x] P05 周／月按天绘制摄入柱、消耗虚线；同 kcal 坐标，点选不改变时间窗口。
- [x] P06 年按月汇总；均值按有效天数加权，不能平均每月均值。
- [x] P07 图表选中条两行排列，查看当天／该月下钻；历史可回查，未来不造数。
- [x] P08 训练按逻辑组统计天数、组数、容量；身体使用真实测量日期，不插值造事实。
- [x] P09 共用原记录详情和当日训练分享；保留已有编辑、删除、分享逻辑。进展日页分享入口 UI 回归通过。
- [ ] P10 浅／深色、44pt 点击、Dynamic Type、VoiceOver；清除装饰说明文案，不删单位、图例、必要状态。
- [x] P11 底部六个资源入口改为语义图标小卡片；默认三列，大字号两列，保留顺序、目的地与完整触达。浅深色、几何、大字号及六项导航回归通过；小屏与 iPad 已检查。

## 动态消耗预估

- [x] E01 训练／饮食累计未知项按 0 相加，保留未知数量与原始 nil，不作为校准零值。
- [ ] E02 读取历史静息与活动能量，区分无数据、错误、真实零；来源去重、取消及演示空间隔离。
- [x] E03 仅使用目标日期之前已完成且覆盖充分的设备日，计算动态有效系数；移除当天活动线性放大。算法测试通过，真实设备覆盖验证另记 E02/D07。
- [x] E04 无充分设备历史时使用用户明确设置、带生效日期的生活方式参考；不擅自套固定系数。
- [x] E05 历史估算使用当时可用体重、年龄及基准；不使用未来数据或将静息当作总消耗。
- [x] E06 系数已包含活动，不额外叠加训练；估算详情提供公式、来源、日期、覆盖与缺失原因。
- [x] E07 参数为可测试的产品策略，不冒充生理定律；不实现未经验证的短期体重／摄入反推。

## 数据、测试与交付

- [x] D01 有界、可取消的独立读取 Context，输出不可变 DTO；增量失效，不在 body 聚合查询。
- [x] D02 日历、累计、加权、历史因果、动态系数确定性测试，先记录失败再修复。
- [ ] D03 临时磁盘 ModelContainer 验证空间隔离、记录更新、跨期查询、加载失败保留旧画面。
- [ ] D04 UI 测试日历、四周期、点选下钻、返回保持、空态、长记录、主题与字号。
- [x] D05 同步 PRD／ADR、数据库（如改字段）、验收与索引；所有旧决策修订双向链接。
- [x] D06 局部测试、make check、make verify，分别记录结果，不复用旧报告。2026-09-05 最终批次通过；之后若修改代码须重新验证。
- [x] D07a Release 安装并正常启动到 14 Pro Max／17 Pro Max。
- [ ] D07b 真实 HealthKit 历史、操作流畅度与 VoiceOver 验收，不能用安装成功代替。
- [x] D08 仅提交本次范围并推送：`8bfecf9`；本地通过证据见下。

## 验证记录

### 2026-09-05 本轮

- 累计未知项回归：先复现 2 个测试失败，修复后通过；原始 nil 和缺失数量保留。
- 第一批完整单测 725 项通过；后续磁盘查询测试发现 SwiftData 不支持可选值强解包 predicate，改为标量 coalesce 后单项复测通过。
- 四周期日期、历史估算、均值、已知小计、独立读取和来源详情已经接入；未完成整体验收的 TODO 不提前勾选。
- `ProgressHistoryUITests` 2 项通过：深色四周期、历史日切 Tab 保持；浅色下钻返回和日历选日。截图在 `build/progress-ui-evidence/`。
- 截图复核发现 Charts 把双 x 范围的 BarMark 绘制成水平短线；已改显式零基线 RectangleMark，待重新截图。
- 旧的当天活动线性外推计算器、来源浮层和对应旧测试已删除；新动态估算不再依赖这条路径。
- 正在收尾训练／身体详情图表、更新后的回归和多尺寸 QA；尚未进行本轮真机安装、HealthKit 验收或提交推送。
- 后续 5 项 UI 测试通过，新增真实点图选择且周期不变；未来下一步置灰，日历限制到今天。
- 日视图移除训练单柱和孤立体重点；多周期也只在至少两个有效点时显示小图。
- 完整 `make verify` 阶段通过 722 项单测，最后变更仍待复跑；测试数量减少来自删除已替代的线性外推／旧浮层用例，不是跳过失败测试。
- 最后一次 `build/progress-final-verify.log`：静态门禁、构建、725 项 XCTest 与 7 项 Swift Testing 全部通过。新增保存失效测试先复现两个失败断言，再修复：个人资料变化刷新进展，聊天流式保存不再触发进展重算。
- `build/progress-final-ui.log`：5 项 UI 回归全部通过，包含日视图不再生成两张小图、未来禁用、浅深色、大字号、点选、下钻和返回；截图在 `build/progress-ui-evidence-final/`。
- `build/progress-share-regression.log`：原训练历史的整日分享回归通过；进展日页新入口的独立分享验收仍待补齐，P09 不提前完成。
- 小屏 iPhone 16e 日页浅色已目视确认不出现单柱／孤立点。iPad mini 周页正常，但切到日页后能量标题出现不可见及中部点击无响应现象，须继续定位；P10/D04 尚未完整通过。
- 本轮尚未提交、推送或安装真机；真实 HealthKit 覆盖与帧率仍是独立待验收项。
- 收尾回归：标题整行点击先复现 24pt 触达失败，补充显式 contentShape 后测试通过；iPad mini 重新安装检查，日页标题和明细均完整可见。最新 `build/progress-ready-verify.log` 静态、构建、725 项 XCTest / 7 项 Swift Testing 通过。新增进展日页分享回归待运行，Release 安装进行中。
- 最新交付：17 Pro Max Release 0.0.18 (22) 已安装并启动（`build/progress-release-17pm.log`）；14 Pro Max 已重新连接，待最终版本安装。进展日页分享新增 UI 回归通过（`build/progress-delivery-ui.log`），iPad 日页和能量依据目视复核通过；真实 HealthKit、VoiceOver 和全场景真机性能不视为已验收。
- 收尾 UI 批次：7 项全部通过，123 秒；记录在 `build/progress-delivery-ui.log`。单柱／孤立点、日页分享、依据整行触达、四周期及大字号均有回归。
- 最终交付：进展提交 `8bfecf9` 已推送。2026-09-05 Release 0.0.18 (22) 已安装并正常启动到两机（`build/fifth-round-release-14pm.log`、`build/fifth-round-release-17pm.log` 和对应正常启动日志）；真实 HealthKit 与 VoiceOver 保持未验收。
- 底部入口补充：旧链接辅助功能几何仅 18pt 高，测试先失败；改为 88pt 起的完整卡片与按下反馈。大字号先复现行高错位，统一两行文字区域后 3 项 UI 测试全部通过（`build/progress-resources-final-ui.log`）；浅深色和大字号截图在 `build/progress-resources-ui-final/`。不改变六个入口的目的地、顺序或任何数据规则。
- 底部入口最终门禁：`build/progress-resources-verify.log` 的 `make verify` 通过，727 项 XCTest、7 项 Swift Testing；Server 39 项通过、1 项测试库未配置而跳过。双机 Release 安装/启动分别记录在 `build/progress-resources-install-14pm.log` 与 `build/progress-resources-install-17pm.log`，不复用此前安装结果。
