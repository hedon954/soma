# BUG 0077 · 关闭补餐提醒的生效范围

- 上游依据：[PRD 082](../prd/082-coach-progress-reliability.md)

## 症状

教练页点击「×」后，即使当天或过去几天仍有待补餐次，同一天内重新进入也看不到提醒。

## 根因

关闭状态按自然日写入 App 偏好，导致其他访问和进程重启继续使用同一日的关闭状态。

## 修复

关闭状态仅保存到当前视图。切回教练、App 进入后台或提醒日期变化时清除关闭状态。再次进入时按当前实际待补餐次决定是否显示。最后一餐标记「没吃」可继续撤销，此时只展示撤销操作。

## 回归门禁

`LibraryAndMealsUITests.testMealBackfillReturnsOnReentryUntilAllDueMealsAreResolved` 检查点「×」立即收起，切 Tab 或进后台再回来时提醒恢复。全部待补餐次标记「没吃」后，关闭按钮及补餐提醒在本次与下一次教练访问中均不显示。
