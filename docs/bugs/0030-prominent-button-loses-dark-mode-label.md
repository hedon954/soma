# BUG 0030：深色模式实心主按钮丢失文字

- 状态：已修复，待真机界面复验
- 日期：2026-08-23
- 下游落地：[PRD 042](../archive/0.0.11/prd/042-user-controlled-recovery-message-feedback-and-action-art.md)

## 症状

训练计划底部“开始训练”在深色模式只显示白色胶囊，文字完全不可见；迁移、带练、分享和反馈中的
同类实心按钮存在相同风险。

## 根因

根 View 的 `tint` 在深色模式为白色，系统 `borderedProminent` 同时推导出白色实心底；label 又沿用
白色默认前景，形成白底白字。颜色值本身有对比度测试，但按钮样式没有显式绑定 `onAccent`。

## 修复

- 新增 Soma 实心主按钮样式，显式使用 `accent/onAccent`，禁用态和按下态仍保持可辨认。
- destructive 实心操作使用独立红底白字样式。
- 全仓替换原始 `borderedProminent`，覆盖训练计划、带练、反馈、分享与迁移恢复。

## 回归门禁

- `scripts/validate-repository.sh` 禁止业务 Swift 文件重新使用原始 `.buttonStyle(.borderedProminent)`。
- `AppThemePaletteTests` 继续验证浅深主题 `accent/onAccent` 的对比度。
- iPhone 模拟器与真机分别检查浅色/深色、禁用态、Dynamic Type 和底部安全区。
