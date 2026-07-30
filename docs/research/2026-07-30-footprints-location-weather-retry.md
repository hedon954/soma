# 足迹、位置、天气与 Agent 重试技术调研

- 日期：2026-07-30
- 结论：采用聊天事实投影、一次性前台定位、按需 Open-Meteo 和持久化跨 Attempt 幂等。

## 现状

- `CoachMessage` 已经持久化用户原始文字和完整有序媒体，是足迹的事实来源。
- `MediaAttachmentReference` 指向 App 沙盒文件，Feed 不应复制或重新拥有媒体。
- 当前远程 Agent 一条用户消息创建一条 `AgentTrace`；本地降级回复没有显式成功状态。
- ReAct Agent 只在单次 Loop 的内存集合中按 Tool Call signature 去重；新的重试 Loop 无法
  复用该集合。
- `ConversationProcessingService` 位于 App 生命周期，适合继续管理重试，但应从超长
  `CoachView.swift` 中拆出。

## Core Location

Apple 的 `requestLocation()` 只运行到返回一次位置或错误，符合发送时快照与低功耗目标。
定位授权应在用户使用相关功能时申请，并只使用 `When In Use`。位置服务可能被拒绝、关闭、
降为模糊精度或暂时失败，因此所有分支都必须允许消息继续处理。

地址解析只为用户可读标签服务，不是 Agent 成功条件。iOS 26 使用
`MKReverseGeocodingRequest`；最低 iOS 17 通过 `CLGeocoder` 兼容。

## 健身房匹配

匹配使用 Haversine 距离和用户为场馆保存的半径。只有一个候选场馆且位置精度可接受时才
自动作为本次 Turn 的有效场馆；多个候选或精度差时使用手动当前场馆。匹配不写
`GymProfile.isCurrent`，避免定位误差制造隐藏状态。

## Open-Meteo

Open-Meteo Forecast API 无需 API Key，可返回体感温度、相对湿度、紫外线和降水等当前
条件。非商业免费端点限制每天 10,000 次调用、没有 SLA，并要求按 CC BY 4.0 提供归属；
商业使用需要切换到付费端点。

直接从移动端调用时，服务方会看到 IP 和请求坐标，故障排查日志可能保留坐标最多 90 天。
因此 Soma 把坐标降到小数点后两位，只在文本命中户外/天气语义时调用，并在内存中转换为
高温、严寒、高湿、高紫外线或降水等一般风险提示。提示被注入本次 Agent 请求，但不进入
Trace 上下文快照；服务失败时返回空上下文。

## 重试与幂等

Turn 与 Attempt 分离后，重试可以复用原始内容并保留失败证据。跨 Attempt 幂等不能依赖
内存集合，因此成功 mutation Tool Call 要写入本地回执。回执键由 Turn ID 和经过 sorted
JSON 编码的 Tool Call 组成；相同调用返回首次 `AgentToolResult`。

媒体重试从 `MediaStore.url(at:)` 重新读取图片或抽取视频关键帧，不依赖系统照片选择器提供
的临时 URL。

## 跨 Turn 业务合并

截图复现显示：首次图片调用 `record_meal` 后，用户补充第二张图片并纠正“不是鱼肉”，Agent
查询历史后再次调用同一个新增工具。因为参数标题已改变，这既不会命中单 Loop signature，
也不会命中跨 Attempt 精确回执。

修复需要把“调用是否相同”和“现实事件是否相同”分开：

- 精确幂等处理同一 Turn/Attempt 的重放；
- 查询结果返回稳定 ID，Agent 纠错时优先调用对应 `update_*` 工具；
- 用户当前消息明确要求时，Agent 可调用受限 `delete_record` 删除指定业务记录；
- 语义合并处理跨 Turn 的补图和纠错；
- 语义合并只接受唯一高分候选，分数来自 Session、时间、类型、规范化文本、结构化数值、
  纠错词和媒体；
- 命中后保留原记录 ID 与时间，覆盖有新证据的错误估算，追加去重媒体。

同一策略适用于饮食、训练和身体记录。健身房已有按名称更新的基础，再补齐名称规范化、媒体
路径和器械名称去重。旧数据只合并时间和数值都高度一致的明显重复。

## 验证重点

- Feed 成功门禁与一次发布；
- 失败后重试不新增用户消息；
- 最终回复失败前已经完成的 Tool 写入不重复；
- 旧消息 Turn 迁移；
- 健身房唯一命中、歧义和精度拒绝；
- 天气相关文本判断与失败降级；
- 位置权限拒绝、模糊位置和真机一次性定位；
- 图片与视频重试。

## 参考

- [Core Location](https://developer.apple.com/documentation/corelocation)
- [CLLocationManager.requestLocation](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation())
- [MapKit reverse geocoding](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest)
- [Open-Meteo Forecast API](https://open-meteo.com/en/docs)
- [Open-Meteo Pricing](https://open-meteo.com/en/pricing)
- [Open-Meteo Terms & Privacy](https://open-meteo.com/en/terms)
- [Open-Meteo Licence](https://open-meteo.com/en/licence)
