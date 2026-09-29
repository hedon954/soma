# PRD 059：教练 ID 即时注入、训练卡必填 0 与进展一致性

- 状态：已采纳
- 日期：2026-09-08
- 版本：0.0.23
- 修订自：[PRD 000](../../../prd/000-origin-through-0.0.11.md) 的缺事实保持空、训练热量、进展估算、快捷建议句、听写预览与助手消息可见性
- 上游依据：
  - [BUG 0037](../../../bugs/0037-insights-snapshot-stale-and-overfetch.md)
  - [BUG 0056](../../../bugs/0056-plan-stats-session-navigation-crash.md)
  - [BUG 0057](../../../bugs/0057-coach-cold-cache-hides-assistant-messages.md)
- 下游落地：
  - [ADR 0126](../adr/0126-workout-share-pro-max-canvas.md)
  - [ADR 0127](../adr/0127-agent-workout-weight-and-rest-zero.md)
  - [验收](../../../acceptance.md)
- 后续修订：
  - [PRD 060](060-remove-healthkit-until-redesign.md)（仅撤回设备能量来源）
  - [PRD 061](061-daily-energy-net-training.md)（仅日总计加入去重后的训练增量；进展列表同时显示容量与热量仍有效）
  - [PRD 062](062-workout-share-fill-or-grow.md)（仅分享导出按动作数铺满或加高；440×956 基准纸面仍有效）

## 背景

纠正已有餐时模型常拿到 UUID 或训练 namespace 的 Int64，要浪费多轮 list/get。训练卡间歇与
重量被省略后显示“—”。进展列表只有容量、分享海报过长、计划训练统计点击崩溃、教练页回前台
只剩用户气泡。

## 用户结果

1. 本机上下文直接给出当日饮食/训练的 Int64 `record_id`，纠正不必试错。
2. 进展日列表每条训练同时给出容量与已估算热量；预估总消耗由 [PRD 061](061-daily-energy-net-training.md)
   在静息 × 系数上加入去重后的训练增量。
3. 训练分享贴合 iPhone 17 Pro Max 纸面，短会话铺满、长会话加高；计划里的训练统计能打开复盘。
4. 教练页写入训练/饮食后，进展当日列表立即一致。
5. Agent 写入的重量与组间间歇未说明时为 0：0kg 是自重，0 秒是没有休息。
6. 左右各做的组数在成对卡片右侧居中；超长标题换行；「训练记录」快捷按钮不再预填句子。
7. 听写预览持续出字，麦克风进入录音态，不再显示「正在本地听写…」。
8. 重新进入 App 仍能看到 AI 消息。可编辑卡保存后有明确「已保存」确认。

## 产品规则

- Agent 上下文与跨轮引用只暴露 Int64 `record_id` / `exercise_id` / `program_id` / `session_id`。
- 进展日列表同时给出容量与已估算热量。日总计公式见 [PRD 061](061-daily-energy-net-training.md)。
- 「训练记录」默认不预填；「近期分析」仍可预填。用户自定义建议句保留。

## 数据与隐私

不新增 SwiftData 字段或远程数据流。测试只用虚构记录。

## 明确不在范围

UUID 到 Int64 的猜测映射。

## 验收

上下文包饮食行含 `record_id:` 且不含 SwiftData UUID；Agent 省略重量/间歇时非最后组为 0；
进展行在有热量时同时显示 kg 与 kcal；分享导出见 [PRD 062](062-workout-share-fill-or-grow.md)；`make verify`。
