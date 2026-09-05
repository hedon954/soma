# 动作库分类与餐次明细视觉 QA

本轮补充（2026-09-05）：分享明细为动作外卡＋合并项内卡。`build/media-qa-unit/` 已检查长动作名、异构组、左右差异与缺失数据导出；`build/media-qa-ui/` 记录 iPhone 17 Pro 正常字号浅深主题、滚动、安全区和保存入口，WorkoutShareUITests 两项通过。页面没有输入键盘。未使用用户健康截图作夹具，未做大字号检查。完整门禁 make verify 已通过：759 XCTest＋7 Swift Testing、服务端 40 项通过（未配置 PostgreSQL 的一项集成测试按既有条件跳过）。物理 iPhone 当前 unavailable，未安装或启动，真实中文准确率与真机声画仍待手动验收。

日期：2026-09-05。按维护者要求使用左侧常驻多级分类与右侧即时结果，正常字号验收。

- 状态：passed。iPhone 17 Pro、iPhone 16e 双主题与 iPad Air 11 英寸竖屏完成检查。
- 截图：`build/library-qa-sidebar/`（17 Pro 1206×2622）、`build/library-qa-small/`（16e 1170×2532）；`library-muscle-ipad.png` 与 `library-pattern-ipad.png` 为 iPad 1640×2360。
- 动作库：左侧身体部位 → 主要肌群的三级路径清晰，选中行有中性色底与竖线；右侧动作可进入详情，返回保持分类与搜索。左右独立滚动，搜索键盘不遮住首批结果，点分类收起键盘。
- 分类交互：部位与下级肌群、动作模式、含辅助的受力肌群均有实际点击证据；空交集可重置，未标注动作保持可达。
- 摄入：早餐橙、午餐绿、下午点心青、晚餐紫、加餐珊瑚色；全部带文字前缀，汇总中性，较长食物名称换行完整。
- 颜色：正常字号数值在实际浅灰／深灰浮层上的对比度均通过 4.5:1 门禁；不改变 App 其他页面的语义色。
- 门禁：`make verify` 通过（756 XCTest + 7 Swift Testing）；`LibraryAndMealsUITests` 在两款 iPhone 的浅深主题通过。
- 范围：维护者要求后续无需大字号检查和适配，本次仅保留正常字号验收。未把用户截图中的真实记录转成夹具。

---

# 训练分享海报视觉 QA

日期：2026-09-05。视觉目标为维护者选定的白底黑字、橙黄色主视觉海报。范围仅训练分享。

## 来源与环境

- 来源：`build/share-qa/selected-final/reference.png`，853 × 1844 px；对话中维护者明确选定的效果图。
- 原生实现：`build/share-qa/selected-final/poster.png`，780 × 1720 px，390 pt 宽、2× ImageRenderer 导出。
- 完整比较：`build/share-qa/selected-final/comparison.png`；来源等比例归一到 780 px 宽，与原生导出并排。
- 明细局部比较：`build/share-qa/selected-final/details-comparison.png`。
- 状态：相同的六动作虚构训练、容量 5,840 kg、22 组、预计 187 kcal、约 35 分 38 秒。
- 数据文案的必要差异：真实投影保留左右各「自重」，页脚使用产品文案「本地训练记录」。不把效果图当作事实数据或运行时贴图。

## 比较与修正

1. 首轮 `build/share-qa/selected-first/comparison.png`：P2 容量字过宽而被缩小、总耗时折为两行、头部间隔偏大。改用 iOS 自带 DINCondensed-Bold，调整容量与统计列宽，收紧头部间隔和行距。
2. 第二轮 `build/share-qa/selected-second/comparison.png`：耗时与明细同排；进一步增大容量可用宽度。
3. 最终完整与局部比较确认：白底、黑色文字、橙黄色主视觉、左容量右肌群、三列统计、明细分隔线和页脚色条均落实；无待修复 P0/P1/P2。

## 五项视觉检查

- 字体：中文使用系统字体，容量采用原生窄体大字；14 pt 明细完整可读，大容量自动缩放，长标题与异构明细扩展高度。未拉伸字体或把文字转为图片素材。
- 布局：390 pt 固定纸面，主视觉外边距 14 pt、文字外边距 24 pt；普通动作名与摘要同排，统计耗时保持一行；无水平裁切。
- 配色：纸面纯白、正文纯黑，主视觉 `#FFB536`；主视觉黑字对比度约 11.92:1，白底次要文字约 6.20:1。App 深浅外观导出的海报像素一致。
- 素材：前后肌群图复用仓库 SVG 路径与真实强度映射，专用纸面呈现移除灰色底卡，主次肌群用橙色深浅；不使用生成图里的近似解剖素材。该资产形态差异是事实素材复用边界。
- 文案：所有组段保留，未知重量不是自重；部分完成与失败仍可见；没有生成稿中的虚构成绩、日期或演示标记写入用户记录。

## 交互与边界

- iPhone 17 Pro：浅色和深色 Accessibility XXXL 的 UI 测试通过，打开分享、读取摘要、保存入口、滚动到末尾说明和关闭返回进展均通过。
- iPhone 16e：`iphone16e-top.png` 与 `iphone16e-system-share.png` 位于最终证据目录；确认小屏保存入口、系统分享缩略图和安全区。
- iPad Air 11-inch：同目录 `ipad-top.png`、`ipad-bottom.png`；原生居中弹层的宽度、滚动到保存与说明、关闭均正常。
- 长数据：同目录 `long.png`；百万级容量、长中文标题、不对称左右、缺失重量/热量和部分完成完整保留。
- 键盘：分享页没有输入控件，不出现键盘覆盖；外观和文字大小不影响导出事实。
- 原生运行日志未发现分享渲染相关错误。系统分享面板可正常打开；模拟器结果不替代维护者真机上的相册权限和最终审美验收。

## 工程证据

- `make verify`：静态门禁、模拟器构建、751 项 XCTest 与 7 项 Swift Testing 全部通过。
- `SOMA_TEST_SCHEME=SomaPerformance SOMA_TEST_FILTER=SomaUITests/WorkoutShareUITests make test`：2 项 UI 回归通过。
- 单元测试结果归档：`build/share-qa/selected-unit-tests.xcresult`；UI 导出附件位于 `build/share-qa/selected-ui-final/`。
- 真机安装后由维护者手动启动，不以安装成功宣称 UI 已由维护者验收。

## 剩余细节

P3：系统中文字形与生成稿存在轻微差别；主视觉采用清晰实色，生成稿的纸张噪点不进入原生导出。

final result: passed

---

# 进展页视觉与交互验收

## 范围

- 参考：[选定稿与四周期细化](docs/assets/ui/2026-09-05/progress-refinement/README.md)
- 实现：[PRD 054](docs/prd/054-progress-history-and-periods.md)；进展首页、训练／身体详情、能量依据。
- 数据：`ProgressHistoryTestFixture` 的虚构餐食、体重、训练；未使用真实健康数据截图。
- 主视口：iPhone 17 Pro，402×874pt / 1206×2622px，iOS Simulator 26.3。

## 检查与修复

| 检查 | 结果 |
| --- | --- |
| 层级与主题 | 保留紧凑标题、日历、四周期、能量主图、训练／身体卡、系统四 Tab；深色纯黑，浅色纯白 |
| 柱与线 | 首轮截图发现双 x 范围 BarMark 误成短横线；改为零基线 RectangleMark，第二轮截图确认柱高和坐标一致 |
| 选中与下钻 | 两行选中条；点图更新日期，不改窗口；再点进入日／月，返回保留原周期 |
| 未来日期 | 日历限制到今天；当前周期下一步置灰；不能从图表进入未来 |
| Accessibility XXXL | 首轮数字被分割换行；改用纵向指标和完整数字，第三轮截图确认修复；控件仍可滚动抵达 |
| 记录列表 | 共用原记录详情、肌群主要／辅助不混同；详情 List 移除重复 chevron |
| 文案 | 首页不含“月内可继续选择任意一天”等教学句；仅指标、单位、图例、覆盖与必要状态；公式在能量依据 |
| 日页摘要 | 已移除训练单柱和孤立体重点；iPhone 17 Pro 自动化与 iPhone 16e 浅色截图确认。多周期至少两个有效点才显示小趋势 |

## 可复核证据

- `build/progress-ui-evidence-v3/manifest.json`：4 项 UI 测试对应浅／深色、四周期、下钻、大字号与详情截图。
- `build/progress-ui-evidence-v3/8EA82ACF-611A-4E6C-9D67-49C0CAA881CB.png`：周视图，柱图修复后。
- `build/progress-ui-evidence-v3/DA573A7A-0CC5-4249-90ED-9290BDA9BA65.png`：Accessibility XXXL 数字修复后。
- `build/progress-verify.log`：阶段性 make verify 通过，722 项单元测试；后续修改仍需最后一次完整门禁。
- `build/progress-final-verify.log`：最终批次通过 725 项 XCTest 与 7 项 Swift Testing；静态门禁和构建通过。
- `build/progress-ui-evidence-final/manifest.json`：最后 5 项 UI 测试截图；日视图小图缺席断言通过。
- `build/progress-layout-evidence/iphone16e-day-light.jpg`、`build/progress-layout-evidence/ipad-mini-week-dark.jpg`：小屏日页、iPad 周页目视复核。
- `build/progress-layout-evidence/ipad-mini-day-dark.jpg`、`build/progress-layout-evidence/ipad-mini-energy-sources-dark.jpg`：iPad 切日后标题完整，整行点击进入依据；标题触达回归先失败（24pt），修复后通过（至少 44pt）。
- `build/progress-ready-verify.log`：标题修复后的完整静态、构建、725 项 XCTest 和 7 项 Swift Testing 通过。
- `build/progress-delivery-ui.log`：收尾 7 项 UI 回归全部通过，包含进展日页分享同一训练海报、标题整行触达、四周期和大字号。

## 状态

主视口自动化与截图阶段 **passed**；最终交付门禁仍进行中。
小屏日页浅色及 iPad mini 周／日页、能量依据已通过目视复核；整行标题点击有自动化回归。
Release 真机 HealthKit 历史覆盖和帧率尚未作为通过证据；不能用安装成功替代真实数据验收。
进度见 [TODO](.codex/plans/2026-09-05-progress-redesign-implementation.md)。
