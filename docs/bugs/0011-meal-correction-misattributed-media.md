# BUG 0011：饮食纠错可能把当前图片写入错误记录

- 状态：已修复；真机交互验收待维护者确认
- 发现日期：2026-08-11
- 影响范围：连续发送饮食图片、补图或使用“不是/上一条”等纠错表达时的记录归属
- 上游依据：无
- 下游落地：
  - [ADR 0056](../archive/0.0.4/adr/0056-trusted-selective-multimodal-context.md)
  - [ADR 0059](../archive/0.0.4/adr/0059-precise-tools-and-reviewable-meal-items.md)
  - [PRD 025](../archive/0.0.4/prd/025-trusted-context-direct-video-and-reviewable-meals.md)

## 症状

用户发送一张新的餐食图片后再纠正，Agent 可能读取历史图片并更新两小时内另一条饮食；聊天中
连续出现分析、查询、记录和更新卡片，用户难以判断最终改了哪一餐。

## 根因

历史窗口默认重新附加媒体；`RecordMergePolicy` 用宽泛纠错词触发两小时候选评分，新图片本身
也能增加媒体得分；Tool result 只有长 observation，没有供 UI 和下一轮稳定引用的 typed record ID。

## 修复

- 当前媒体优先且默认不发送历史媒体，回指只恢复最近明确候选。
- 新图片默认创建；更新必须使用精确 record ID，歧义时不写入。
- Tool v2 返回 typed record ref，饮食以单张结果卡展示并进入详情审查。

## 回归门禁

- 自动化测试：新餐、同餐补图、紧邻纠正、多候选和跨 Session 媒体归属。
- 手工验收：使用虚构饮食图片按复现顺序发送，确认卡片记录和详情一致。
- 仍无法自动化的风险：供应商对自然语言回指的理解差异。

## 验证

`make verify` 已通过；iPhone 17 Pro 模拟器已检查浅色、深色、输入状态、滚动、VoiceOver 标签
和最大无障碍字号。使用真实模型与真机图片执行自然语言纠错仍由维护者手工确认。
