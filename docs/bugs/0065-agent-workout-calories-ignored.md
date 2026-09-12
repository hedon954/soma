# BUG 0065：训练工具丢弃用户提供的热量

- 状态：已修复，完整本地门禁通过
- 日期：2026-09-12
- 上游依据：[ADR 0135](../adr/0135-agent-workout-calories.md)

## 症状

用户给出训练热量后，记录仍保存公式估算值。

## 根因

创建／修改的固定 Schema 不接受 `calories`，
批量创建输入未携带该字段，修改工具刷新热量时没有传入已有的 `calorieOverride`。
创建回执也直接引用公式结果，无法表达用户提供的值。

## 修复

将可选 `calories` 从工具 Schema、批量输入一直传到现有热量字段。提供时直接采用，
省略时保持现有 MET 计算。创建回执返回采用值，修改回执从保存后的记录生成。

## 回归门禁

`AgentWorkoutCaloriesTests` 从 JSON 校验、解码、工具执行到新 ModelContext 读取持久值，覆盖
创建／修改各自有值、无值四种路径，以及零、缺体重和幂等签名。测试只使用虚构数据。
`Server/test/workout-calories.test.ts` 验证远程端相同的四种 Schema 输入。
修复前，有值路径因未声明 `calories` 失败；修复后须通过 `make check`、`make verify`。
