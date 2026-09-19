# PRD 052：教练、训练与生命周期可靠性

- 状态：已实施；待 Release 真机验收
- 日期：2026-09-02
- 修订自：
  - [PRD 047](../../0.0.16/prd/047-root-aware-tab-reselection.md) 的教练 Tab 再选行为
  - [PRD 000](../../../prd/000-origin-through-0.0.11.md) 的前台恢复响应边界
- 后续修订：[PRD 058](../../0.0.22/prd/058-feedback-duration-and-editable-calories.md)（时长时分秒展示与可编辑预计消耗）
- 后续修订：[ADR 0125](../../0.0.22/adr/0125-eager-loaded-coach-messages.md)（已加载消息即时排版，滑动不再懒卸载）
- 上游依据：
  - 维护者提供的十七项严重 Bug、界面截图与崩溃报告
  - [BUG 0045](../../../bugs/0045-guided-workout-coredata-abort.md)
  - [BUG 0046](../../../bugs/0046-coach-stream-scrolls-into-blank-space.md)
  - [BUG 0055](../../../bugs/0055-coach-history-scroll-repositions.md)
  - [BUG 0047](../../../bugs/0047-terminal-failure-retry-leaves-stale-error.md)
  - [BUG 0048](../../../bugs/0048-speech-segment-overwrites-committed-text.md)
  - [BUG 0049](../../../bugs/0049-quick-camera-presentation-deadlock.md)
  - [BUG 0050](../../../bugs/0050-coach-foreground-recovery-freezes-again.md)
- 下游落地：
  - [ADR 0110](../adr/0110-workout-tool-and-calorie-evidence.md)
  - [ADR 0111](../adr/0111-agent-response-identity-and-manual-recovery.md)
  - [ADR 0112](../adr/0112-coach-scroll-and-session-behavior.md)
  - [ADR 0113](../adr/0113-capture-and-foreground-lifecycle.md)
  - [ADR 0125](../../0.0.22/adr/0125-eager-loaded-coach-messages.md)
- 后续修订：[PRD 056](../../0.0.22/prd/056-video-speech-and-share-readability.md)（仅视频、语音或分享明细相关部分）

## 背景

训练事实进入 Soma 后仍可能被冗长展开、误判侧别或缺失热量；教练消息在排队、失败、重试和流式
增长时缺少稳定身份与滚动边界；快捷相机、带练和前台恢复还存在无法退出、崩溃或短时冻结。这些
问题共同破坏“自然表达 → 确定性工具 → 可审查记录”的主路径，必须作为一个端到端可靠性版本收口。

## 用户结果

1. 相同训练组以一段紧凑摘要呈现；记录卡保留完整动作名、正确侧别、自重语义和可审查逐组事实。
2. Agent 收到请求后立即出现一个响应；等待、执行、失败和人工重试都在同一气泡原位变化。
3. 模型只看到设备业务时区的权威本地时间；Session 默认以 `MM月dd日 - 周X` 命名。
4. 教练首次进入、打开 Session、切回或发送时定位到最后一条消息末尾；短内容贴顶，用户上滑后不抢位置。流式增长仍跟随最后一条 AI 消息尾部。
   已加载的一页消息一次排版，滑动过程不再因懒卸载改高度；只有到顶分页才增加 30 条。
   画过的记录卡和完成态正文常驻缓存，切 Tab 或 Session 命中后不再重画。
   单次再选教练保持原位，只有系统双击回到尾部。
5. 语音停顿形成已提交片段，继续说话只会追加；普通训练与带练在证据充分时显示推算热量。
6. 带练保存、恢复、退出或删除失败时保留数据并提示，不以外围 `do/catch` 掩盖 `SIGABRT`。
7. 桌面、锁屏或 App Shortcut 快速拍照可以拍摄、取消或进入设置；锁屏/后台会安全结束，不留下
   无法关闭的 Modal。
8. 从后台或锁屏回到教练页时先显示缓存快照并立即可滑动、输入，恢复工作在首帧之后可取消执行。
9. 计划训练复盘中的每个动作直接复用进展页训练记录行，显示压缩组次、容量和时间，并进入同一
   训练记录详情；用户已经删除的投影只显示“训练记录已删除”。
10. 训练详情的受力图进入即展开；聊天训练卡底部同一行显示“添加一组”和右对齐热量；AI 时间、
    日志、反馈及记录卡尾随操作紧凑但保持独立 44pt 触达。
11. Agent 已接收与模型处理中使用同一种过程样式；Tool/Skill 从准备、执行、等待设备到终态始终
    原位流转，不突然只出现结果卡，也不暴露内部函数名、参数 JSON 或 operation ID。

## 产品规则

- 训练 Tool v4 必须显式携带目标类型、动作侧别、逻辑组序号、effort 侧别与逐组间歇；旧版本只
  用于恢复已持久化任务，不向新模型调用广告。
- 本次训练的显式 evidence 优先于动作库元数据；证据不足时才 fallback，禁止反向覆盖用户事实。
- 热量只使用训练发生时点之前最近体重与完整训练证据；真实时长优先，否则每次约 4 秒加已记录
  间歇，并标为推算。缺事实保持 `nil`。
- 快捷相机由根层单一状态机独占展示；重复 URL 在未完成阶段幂等，终态后可开始新请求。
- 前台恢复不得重选 Session、重置草稿或滚动位置，也不得让网络、备份或无界历史扫描占用首个
  可交互区间。
- 带练页面及子视图不得持有 Session/Performance/Set/Effort SwiftData 对象；只渲染按标量 ID
  构建的不可变快照。可抛出错误提供恢复，CoreData abort 由移除危险查询解决。
- Agent 临时状态不写入消息正文；本地和远程使用同一 operation 阶段契约，重复或重放事件只能
  更新原卡。

## 数据与隐私

- 不新增远程身体事实；Tool v4 的训练参数仍经既有本地/远程 Agent 协议，业务记录只在设备落地。
- `titleSourceRaw` 仅保留为已安装数据库兼容字段，不再读取或写入。
- 生命周期 breadcrumb 和 signpost 只记录阶段、稳定匿名 ID 与错误类型，不记录动作名、重量、身体
  数据、消息正文、媒体路径或密钥。
- 当前 Session 渲染快照是最多 10 条、总成本不超过 2 MB 的不可变 DTO，不持有 SwiftData 对象。

## 明确不在范围

- 不删除每张动作卡现有的“添加一组”。
- 不用猜测值补齐缺失重量、间歇、体重、时长或侧别。
- 不把 Simulator、静态检查或无符号 dSYM 的崩溃报告当成 Release 真机完成证据。

## 验收

- 确定性单元/集成测试覆盖压缩、Schema v4、时间、命名、语音累计、热量、消息身份、相机状态机、
  前台 generation 和 SwiftData FIFO 稳定 ID。
- 模拟器覆盖长动作名、Dynamic Type、失败重试、初始定位、流式增长、左滑删除和相机失败态。
- 模拟器额外覆盖计划复盘复用行、受力图默认出现，以及 Activity/Tool/Skill 每个阶段的可控夹具。
- Release 真机完成带练至少十次生命周期、语音两次停顿、桌面/锁屏相机各 10 次与长会话前台恢复；warm
  可交互 p95 `<100ms`，无 `>100ms` 主线程停顿、Hangs 或重复崩溃。
- `make check`、`make verify` 通过；真机门禁未完成的项目保持“待验收”。
