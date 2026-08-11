# Soma 对话上下文、视频链路与饮食交互改进计划

- 日期：2026-08-11
- 状态：已实施；自动化与模拟器验收通过，真机交互待维护者确认
- 目标：修复跨日 Session、上下文错乱、视频传输与首响应性能问题，收敛 Agent Tool，并改进饮食记录的可审查交互。

## Summary

- 当前跨日不新建 Session 不是普通回归：Accepted ADR 0022 明确选择了“用户控制、跨日不切换”，需要以新 PRD/ADR 正式改回“进入前台时按设备自然日解析 Session”。
- 上下文混乱来自四层叠加：本地历史、结构化上下文、Tool 长文本结果互相重复；历史媒体引用过宽；饮食纠错用“两小时内候选评分”猜记录；远程 Agent 又只收到当前消息和结构化快照，没有本地最近 10 轮历史。
- 当前百炼/Qwen 路径会发送整个视频，但请求同时携带已抽取的关键帧，准备阶段也总会抽帧；其他本地模型和所有远程任务只收到关键帧。改为能力注册驱动的“直传优先、按需降级”，并明确记录实际分析模式。
- 当前没有 TTFT watchdog：普通流依赖 SDK 默认行为，直传视频只有 180 秒请求超时，Server provider 没有主动取消。采用文字 8 秒、图片 10 秒、直传视频 20 秒，每个模型步骤最多自动重试一次。
- 饮食交互采用“餐次总览 + 食物项”，不复制 Keep 的品牌样式、快捷入口和推荐问题，只保留一张可编辑结果卡及简短教练说明。

## 1. 产品与协议契约

- 新增 PRD 025，统一定义跨日 Session、可信时间上下文、选择性历史、视频传输、TTFT、Tool v2 和饮食结果卡的用户验收边界。
- 新增 ADR 0055–0059，分别覆盖：
  - 按自然日自动解析 Session，部分替代 ADR 0022，并明确 ADR 0015 中恢复生效的边界。
  - 本地/远程一致的可信上下文与选择性多模态引用，部分替代 ADR 0024、0047。
  - 直传视频能力注册及可观察降级，衔接 Bug 0002。
  - 首增量超时、取消、单次重试和延迟分段，衔接 ADR 0037 与 Bug 0005。
  - Tool Schema v2、精细查询、通用记录 CRUD 和饮食分项模型，部分替代 ADR 0028、0050。
- 新增 Bug 0011“饮食纠错误关联历史媒体”和 Bug 0012“直传视频重复送帧且缺少 TTFT 门禁”；同步双向生命周期链接、目录索引、验收矩阵、Agent/远程协议文档和 CHANGELOG。

## 2. Session、时间与上下文

- App 冷启动、根视图进入和 `scenePhase == .active` 时：
  - 最新用户消息属于今天：复用其 Session。
  - 今天已有唯一空 Session：复用它。
  - 否则创建并持久化今天的新 Session。
  - 演示/个人数据空间分别解析，连续激活不得创建重复空 Session。
- App 跨午夜保持前台时，在发送前再次执行同一解析；用户手动选择旧 Session 后，本次前台生命周期内允许继续旧会话，重新进入前台后恢复自动按日解析。正在执行的 Turn 始终绑定提交时的原 Session。
- 新增不可被用户提示覆盖的 `TrustedTurnContext`：
  - `turn_sent_at`：用户消息提交时间。
  - `attempt_started_at`：每次模型尝试的实际时间。
  - `timezone_identifier`、UTC offset、设备本地日期与星期。
  - “今天/刚才/晚餐”等相对时间以 `turn_sent_at` 解释，“现在”以 `attempt_started_at` 解释。
- 将本地和远程输入统一为 `AgentTurnContextEnvelope v2`：可信时间、业务摘要、最近会话文本、短格式事实引用、当前/明确引用的媒体。
- 最近历史最多 10 个完整来回，同时受约 6,000 token 的历史预算约束；优先保留最新完整 Turn，不截断半个 Turn。较早成功写入只保留短事实引用：操作、记录类型、稳定 ID、标题和时间，不重复 Tool 的整段 observation。
- 历史媒体选择规则：
  - 当前 Turn 有媒体时只发送当前媒体。
  - “上一张/刚才/那个视频”等明确回指只加入最近一个匹配 Turn。
  - 明确比较时最多加入两个匹配 Turn。
  - 其他情况历史只传文字；不得把历史图片归因给当前记录。
- 饮食更新必须绑定稳定 `record_id`。新图片默认创建新记录；只有“补充上一餐/修正刚才记录”等明确指代且紧邻 Turn 只有一个候选时才更新。多个候选时先询问，不进行猜测性写入。

## 3. 视频与响应速度

- 建立 provider/model 媒体能力注册表，不再用宽泛的模型名称猜测。首批只为经过协议验证的百炼/Qwen 开启直传；视频先转为兼容 MP4，并将原始文件控制在安全的约 7 MB 以内。
- OpenAI、未验证的腾讯 TokenHub 与 OpenCode 路由使用明确标注的关键帧模式，不宣称完整视频理解。
- 直传路径首请求只发送完整视频，不预抽帧、不同时发送帧；远程模式上传规范化视频并由 Server 组装同样的 `video_url` 数据。
- 只有直传在首增量前失败或超时，才按需抽取关键帧并消耗唯一一次重试机会。关键帧降级必须在 Trace 和回复中标明，不能静默伪装成完整视频分析。
- 每个模型步骤从请求真正发出后开始 TTFT 计时；首个非空文字增量或 Tool Call 增量均算首响应：
  - 纯文字：8 秒。
  - 图片/关键帧：10 秒。
  - 直传视频：20 秒。
  - 最多自动重试 1 次；收到首增量后采用 30 秒流空闲超时和 180 秒单步骤总时限。
- 超时取消底层 URLSession/fetch；Server 使用 `AbortController`。重试留在同一 Agent Attempt/Trace 内，增加独立模型请求 Span，尚未形成完整 Tool Call 时不得产生业务副作用。
- Trace 分别记录媒体准备、上下文投影、上传、provider TTFT、流式生成和总耗时，并增加 `media_mode`、视频字节数、帧数、TTFT budget、timeout phase、request attempt 与 fallback reason。

## 4. Tool Schema v2 与饮食数据

- 当前统一返回 `{ok, observation: String, record_type?}`；改为紧凑结构化 envelope：`{ok, code, message, data?, record_refs?, page?}`。聊天 UI 根据 typed result 渲染，模型只收到请求字段和短消息。
- `query_user_data v2` 输入：
  - `scope`，以及按需的 `record_id/exercise_id/program_id/session_id`。
  - `query`、`date_from/date_to`、`sort`、`limit`（默认 3、最大 10）、`cursor`。
  - `projection=summary|detail`、按 scope 校验的 `fields[]`。
  - 聚合专用 `group_by/metric`。
- 所有过滤条件必须真实生效；`detail` 必须带精确 ID；动作库必须带搜索词；列表一律分页，不再返回全库；响应为 `items + next_cursor`。
- 新增 `mutate_user_data(operation, record_type, record_id?, payload?)`，只合并训练、饮食、身体三类 CRUD。运行时严格校验 operation、record type、record ID 和唯一对应 payload；删除继续要求当前用户消息明确授权。
- Tool Schema 升级为 v2；远程 Job 协议同时携带 tool name 与 schema version。Server 和设备在迁移期继续接受 v1，历史 Job、备份和持久化 Tool Call 通过隐藏别名执行，不再暴露给新模型。
- 新模型实际暴露 13 个 Tool：
  - Core：`load_skill`、`query_user_data`、`mutate_user_data`、`expand_tool_group`。
  - Plans：`create_training_program`、`create_workout_template_version`、`archive_training_program`、`delete_training_program`、`start_guided_workout`。
  - Gym：`update_gym`、`switch_gym`。
  - Review：`record_performance_analysis`。
  - Feedback：`submit_feedback`。
- `list_exercise_names`、`list_training_programs`、`get_training_program` 并入精确查询；六个记录写工具及 `delete_record` 并入通用 CRUD；`update_workout_template` 保留为 `create_workout_template_version` 的隐藏兼容别名。远程提交只暴露与本地相同的初始工具组，不再一次发送全部 Tool。

## 5. 饮食结果与编辑体验

- `MealEntry` 的热量和三大营养改为可空，旧值原样迁移为已有估算；新增有序 `MealItem`：稳定 ID、名称、份量说明、可空热量/蛋白质/碳水/脂肪。
- 增加营养来源 `aiEstimate/derivedFromItems/userEdited/imported`。只有所有相关食物项均有该营养值时才可自动汇总；否则总值保持未知并显示“—”，不得再用 0 冒充事实。用户编辑的总值优先于派生值。
- 饮食 Tool payload 支持 `items[]` 和可空汇总营养。现有无分项记录继续显示原总值，不伪造食物拆分。
- 成功记录或更新后，聊天只展示一张饮食结果卡：照片、餐次与时间、标题、大号 kcal 或“未估算”、三大营养、前三个食物项，以及进入详情的“查看并编辑”。
- 原来的多张过程卡折叠成一个小状态摘要；教练回复最多补充两句不重复卡片的数据。
- 详情页支持食物项新增、删除、排序和编辑；宏量营养及说明继续渐进披露。验证无图片、未知营养、长食物名、Dynamic Type、VoiceOver、浅色/深色；不增加 Keep 的品牌色、底部快捷操作条或推荐问题 chips。

## 6. 当前 Tool 审计

当前共 23 个 Tool，统一返回字符串 observation：

- Core：`load_skill`、`query_user_data`、`list_exercise_names`、`record_workout`、`record_meal`、`record_body`、`update_workout`、`update_meal`、`update_body`、`delete_record`、`expand_tool_group`。
- Plans：`list_training_programs`、`get_training_program`、`create_training_program`、`create_workout_template_version`、`update_workout_template`、`archive_training_program`、`delete_training_program`、`start_guided_workout`。
- Gym：`update_gym`、`switch_gym`。
- Review：`record_performance_analysis`。
- Feedback：`submit_feedback`。

主要问题是全库动作/计划无分页返回、读取能力重叠、记录 CRUD 名称爆炸、模板更新别名重复、普通查询过滤不完整、字符串结果难以供 UI 精确呈现。

## 7. Test and acceptance plan

- 单元测试覆盖跨日新建、当天复用、重复 foreground、跨午夜发送、手动继续旧 Session、数据空间隔离和执行中 Turn 归属。
- 使用固定 Clock 验证可信时间、时区和远程恢复；本地与远程对同一输入生成相同的文本历史与事实引用。
- 构造“新图片记录新餐”“补充上一餐”“不是这个、是当前图片”“多个候选”回归测试，证明不会再靠两小时评分误改记录。
- 使用可注入流和虚拟时钟验证 8/10/20 秒 TTFT、唯一一次重试、首 Tool delta、30 秒 idle、180 秒总时限、取消传播以及无重复 Tool 写入。
- 验证百炼直传首请求不含关键帧；不支持的视频模型只收到关键帧；直传失败后才抽帧；本地和远程 Trace 均准确记录实际模式。
- 对 Tool v1/v2、分页 cursor、fields 投影、日期过滤、动作搜索、隐藏别名和远程协议兼容做确定性测试。
- 验证旧饮食数据迁移、未知营养不显示 0、分项汇总规则、编辑保存、备份导入导出和演示/个人空间隔离。
- 运行 `make check`、`make verify`，并在 iPhone 尺寸模拟器检查饮食流程、浅色/深色、键盘、滚动和辅助功能。
- 验证通过后使用任务范围 Conventional Commit 提交并推送，执行 `make install-device`；真机手工交互验收保留为维护者确认项，不进行外部分发或公开发布。
