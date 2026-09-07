# BUG 0049：快捷相机展示卡死且无法取消

- 状态：已修复代码路径，待桌面与锁屏 Release 真机复验
- 发现日期：2026-09-02
- 影响范围：桌面 Widget、锁屏 Widget、App Shortcut 快速拍照
- 上游依据：维护者真机反馈
- 下游落地：
  - [PRD 052](../archive/0.0.19/prd/052-coach-training-and-lifecycle-reliability.md)
  - [ADR 0113](../archive/0.0.19/adr/0113-capture-and-foreground-lifecycle.md)

## 症状

从系统快捷入口进入 Soma 并唤起拍照时，偶发相机不能拍摄且取消无效，只能强杀 App。

## 根因

快捷请求先切 Tab，再展示外层媒体 Sheet，随后内层相机 Sheet；一次 `Task.yield()` 不能证明 Scene
active 或窗口层级可展示。取消只关闭 Picker，没有结束快捷请求，重复深链又能与旧展示竞争。

## 修复

- 系统入口统一深链到根层状态机；等待 active Scene 和窗口后，用单一顶层 `fullScreenCover` 展示相机。
- pending/presenting 重复 URL 幂等；拍摄只交付一次。取消、权限拒绝、设备无相机、进入后台或锁屏
  均结束事务并释放相机，恢复后不自动重开。
- 权限/设备失败展示取消、前往设置或选择照片，不静默切换。

## 回归门禁

- 自动化：状态迁移、重复请求、inactive Scene、竞争 Modal、取消和单次交付。
- 手工：Release 真机桌面/锁屏各连续 10 次，覆盖授权允许/拒绝、拍摄、取消和拍摄中锁屏。

## 验证

状态机与 Simulator 路由测试已覆盖；真实相机和系统宿主仍必须真机关闭门禁。
