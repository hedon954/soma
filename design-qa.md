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
