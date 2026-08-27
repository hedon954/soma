# PRD 046：教练记录可信度、会话交互与目标导向进展

- 状态：已采纳，已实施；核心路径已通过模拟器检查，待真机交互验收
- 日期：2026-08-26
- 修订自：
  - [PRD 000](../../../prd/000-origin-through-0.0.11.md) 收口的记录真值、身体信息、聊天元信息、会话分页、
    有界进展快照和 ReAct 运行预算
- 后续修订：
  - [PRD 048](../../../prd/048-reviewable-record-derivation-and-user-controlled-interruption.md)
  - [PRD 049](../../../prd/049-foreground-responsiveness-and-readable-monthly-progress.md)（修订进展时间窗、分项来源与全天消耗预估）
- 上游依据：
  - 维护者提出的十二项功能优化
  - [目标导向进展指标调研](../../../research/2026-08-26-goal-directed-progress-metrics.md)
  - [BUG 0038](../../../bugs/0038-source-workouts-missing-plan-execution.md)
  - [BUG 0039](../../../bugs/0039-meal-occurrence-and-duration-target-truth.md)
- 下游落地：
  - [ADR 0101](../adr/0101-record-truth-and-agent-profile-context.md)
  - [ADR 0102](../adr/0102-source-workout-plan-execution-materialization.md)
  - [ADR 0103](../adr/0103-goal-directed-progress-energy-and-hypertrophy.md)
  - [ADR 0104](../adr/0104-independent-react-timeouts-by-media.md)

## 背景

当前实现同时存在记录真值丢失、模型覆盖本地可确定事实、短会话定位和编辑反馈不完整，以及进展图
缺少目标解释的问题。它们跨越 SwiftData、Agent Tool、SwiftUI 和 HealthKit，必须用同一验收边界
收口，避免只修表面文案后继续产生错误业务记录。

## 用户结果

1. 饮食详情的每个食物项连续排列；列表分隔线不再变成独立空行。详细评价不足五行直接展示，
   超过五行才提供展开/收起；图片无法可靠识别的“总糖”从模型、Tool、界面、备份和导出中移除。
2. 餐次默认由记录发生时刻确定：05–11 早餐、11–14 午餐、14–17 下午点心、17–22 晚餐，其余
   加餐；只有用户原文明确说出餐次时才覆盖，模型参数不能单独改写。
3. 当教练把当日原始训练总结为计划时，同时建立一次已完成 `WorkoutSession`；原始训练记录是
   执行证据，不复制也不丢失，删除该 Session 时原始记录仍保留。
4. 聊天倒序分页读取最近消息。内容不足一屏时顶部对齐；足一屏时首次定位底部，最后一条 AI 回复
   的时间/执行日志/反馈行紧贴输入区上方分隔线。执行日志只定向打开该回复 Trace。
5. 聊天动作卡按动作定义展示“次数”或“秒数”，不出现 A/B/C 前缀。编辑记录卡后自动保存；保存中
   显示旋转进度，成功后勾选由灰变亮并给出触觉确认，失败保持可见。
6. 身体信息不再保存参考体重，始终展示最新体重记录。昵称、生理性别、动态年龄、身高、最新体重、
   健身目标和限制注入本轮 Agent 结构化上下文。
7. 高级设置分别配置文字、图片、视频 ReAct 总超时，范围均为 3–60 分钟，默认 3/5/10。
8. 进展首屏由目标驱动：减脂展示当日摄入、静息消耗、活动消耗和能量结余；增肌展示近 7 天训练
   天数、可计算容量和主要肌群工作组覆盖；增肌减脂同时展示两组。估算数值旁的信息按钮说明来源、
   公式与缺失条件。

## 产品规则

- 本次只做功能级实现修正：使用稳定 row identity、overlay 分隔线、有界查询、异步快照与受控滚动；
  不以本次工作宣称 Release 真机 hitch 或帧预算已经量化达标。
- 食物项、聊天记录卡和消息行不得在 `body` 中做无界查询或同步媒体解码。
- 自动保存使用短防抖合并连续输入，页面离开时仍以 SwiftData 当前编辑事实为准。
- 新按钮提供 VoiceOver label；五行折叠适配 Dynamic Type，不能按字符数猜测是否需要展开。

## 数据与隐私

- 删除 `MealEntry.totalSugar`、`MealItem.totalSugar` 和 `UserProfile.referenceWeight` 是不兼容的
  当前 schema 变更；本地当前版本按既有启动门禁处理，不新增虚假回填，也不保留旧字段影子。
- HealthKit 能量只在设备上读取，未授权时不弹出额外请求；缺失时使用本地可解释估算或保持未知。
- 计划执行、Agent 身体上下文和执行日志入口均不新增身体数据出网；远程仍只接收既有版本化上下文。

## 明确不在范围

- 不在本次建立诊断、个体化热量目标或“达标/不达标”训练阈值。
- 不新增账户、云端身体事实、HealthKit 自动授权弹窗或用户自定义指标插件实现。
- 不执行或宣称本次 Release 真机性能量化；既有性能预算仍由 ADR 0097/0100 独立验收。

## 验收

- 单元测试固定 18:00 默认晚餐、15:30 下午点心、用户明确餐次覆盖、时长动作秒数、身体资料上下文、
  三类超时、Mifflin 公式和原始训练到已完成 Session 的保留/删除语义。
- 静态门禁确认 Swift 与活文档中不再存在总糖或参考体重的当前字段定义。
- 模拟器检查饮食详情、短/长 Session、动作卡自动保存、长评价、进展目标卡和三类超时设置的浅深色、
  Dynamic Type、滚动、键盘与安全区；性能量化仍按既有 ADR 0097/0100 独立执行。
- `make check`、`make verify` 通过。
