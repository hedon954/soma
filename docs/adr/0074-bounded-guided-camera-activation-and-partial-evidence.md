# ADR 0074：带练相机采用完整有界 activation 与部分录像证据

- 状态：已采纳；实现与维护者真机验收进行中
- 日期：2026-08-16
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0039](0039-event-driven-guided-recording-cues-and-review.md) 中“只在开始写文件时才准备相机”、动作介绍阶段不建立可见 camera-ready 状态的 lazy activation 边界
  - [ADR 0073](0073-independent-set-prescriptions-efforts-and-guided-finalization.md) 中 attempt 从写文件请求才拥有完整终态、所有有效文件只分为 `saved/failed` 的粗粒度语义
- 后续替代：暂无
- 上游依据：
  - [PRD 031](../prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
  - [BUG 0020](../bugs/0020-guided-camera-activation-deadline-and-partial-evidence.md)
- 下游落地：
  - [BUG 0022](../bugs/0022-installed-v5-schema-checksum-blocks-container-open.md)
  - [BUG 0025](../bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md)
  - [BUG 0026](../bugs/0026-guided-auto-recording-still-stops-without-reason.md)
  - [PRD 035](../prd/035-guided-preview-then-record-and-immediate-share.md)

## 背景

现有实现把“相机准备”和“开始写文件”拆成两个 await。attempt、八秒启动定时器和用户失败事件
只在准备完成后才建立，而准备过程本身还包含权限返回后的配置、同步阻塞的
`AVCaptureSession.startRunning()` 与连接建立。任一机器阶段不返回时，Coordinator 会永久停在
`isStartingRecording`，既没有 attempt 终态，也没有警告；共享 preparation task 还会让后续重试
继续等待同一个已中毒任务。

同时，执行页只在 `.recording` 时挂载取景器。用户无法分辨权限请求、相机正在启动、已经就绪与
启动失败。系统中断或后台停止后，只要 Delegate 返回非空有效文件和成功 key，极短片段也会被
当作完整录像保存，掩盖“刚唤醒就停止”的真实故障。

Apple 明确指出 `startRunning()` 是阻塞调用，应离开主线程在串行队列执行；官方相机架构也把
Capture Session 生命周期与可见 preview 作为 Capture Service 的明确状态。Soma 保持本地优先和
按需相机，但不能把“按需”解释为“直到用户已经开组才盲启相机”。

## 决策

### 1. 完整 request 在准备前建立

1. 每次自动或手动录像请求先建立唯一 request/attempt ID，再进入权限、配置、Session 启动、
   connection 验证和文件写入。
2. 所有阶段都归属于同一 request，并且只能收敛到一次终态。失败、取消或超时后必须清理正在等待的
   continuation、输出 URL 和当前活动身份；迟到回调只能被忽略，不能复活旧 request。
3. 权限弹窗是用户决策等待，不与机器阶段使用同一个固定截止时间；权限返回后，配置、
   `startRunning()`、video connection readiness 和 `didStartRecordingTo` 分别受有限 deadline 约束。
4. machine deadline 到达时，当前 request 明确失败并投影恢复建议。无法取消的底层阻塞操作可以在
   后台晚到，但由 generation/token 隔离，其结果不能污染新的 retry。
5. retry 必须创建全新 request 和 preparation generation，不复用失败或超时的共享 task。

### 2. camera-ready preflight 可见但仍按需

1. 用户选择“每动作第一组”或“每组录像”后，Soma 在动作介绍或开组倒计时阶段启动 preflight，
   先达到 `.ready` 再由目标 Effort 发出写文件命令；preflight 失败不阻断训练。
2. 用户选择“不录像”时不申请、不启动、不占用相机。只有点击常驻录像按钮后才进行相同 preflight，
   并把意图绑定到当前可录 Effort或下一个有效 Effort；没有目标时给出明确反馈，不能静默返回。
3. 执行页为 `requestingPermission / configuring / startingSession / ready / startingRecording /
   recording / unavailable` 提供可访问的内联状态。preview 在 `.ready` 即可见，不再等待真正写文件。
4. 红点仍只代表 `didStartRecordingTo` 已确认，`.ready` 和 `.startingRecording` 不得伪装为正在录像。

### 3. Capture Session 使用显式有限状态机

1. Session 配置、start/stop、连接读取与方向更新在单一串行执行域中完成；UI 只消费不可变状态投影。
2. 写文件前验证 Session 正在运行、没有活动中断、movie output 的 video connection 存在、enabled
   且 active；条件不满足时恢复或明确失败，不能把命令发送到无效连接后继续等待 Delegate。
3. 监听 interruption began/ended、media services reset 和 App foreground/active 事件。中断结束或回到
   前台时重新验证连接；媒体服务重置或 Session 失效时重建配置。
4. 自动录像失败可以暂停本 Session 后续自动 request，但暂停原因必须保持可见；用户手动成功 retry
   后才清除。View 重建不能仅恢复 pause 布尔值又清空告警。

### 4. 完整成功与部分证据分开

1. 用户明确停止、Effort 正常结束，且系统确认文件有效时为 `saved`。
2. 系统中断、后台、启动/结束超时或其他异常提前终止时，若文件可读且非空，保留为
   `savedPartial`，绑定原 Effort 并给出一次用户警告；训练事实继续保存。
3. success key 只证明 AVFoundation 成功收尾当前文件，不证明它覆盖了 Soma 期望的完整 Effort。
   因此异常 stop reason 不能仅凭 success key 升格为 `saved`。
4. `failed/cancelled` 无可用文件；删除只针对当前 request 所有且确定无效的临时文件。
5. 终态与提示按 request ID 去重。`savedPartial` 的后续幂等 stop 不产生第二个 Alert。

### 5. 可诊断但不泄露训练事实

阶段化日志至少记录 request ID、授权结果、配置与 Session 命令、运行/中断布尔值、video connection
readiness、movie command、Delegate start/finish、stop reason、success key、文件有效性和终态。
日志不得记录视频路径、动作名称、处方、重量、身体数据或帧内容。

## 未选择的方案

- 只给 `didStartRecordingTo` 增加更长 timeout：无法覆盖 timeout 建立之前的权限后配置与
  `startRunning()`，仍会永久悬挂。
- 在 App 启动或计划详情常驻相机：超出用户录像意图并增加隐私与电量成本。
- 只显示 Alert，不显示准备/就绪状态：用户仍无法调整机位，也无法判断按钮有没有生效。
- 只按文件时长设置统一最短阈值：用户主动快速停止是合法操作；必须结合 stop reason 判断部分证据。
- 系统中断后一律删除文件：会丢失真实可播放证据，违反已成功工作不伪装为未发生。
- 继续复用单个 preparation task：一次不可取消的系统调用会毒化本次 Session 的所有重试。

## 结果

### 正向影响

- 从用户点击到写文件开始的整个链路都拥有有限、可解释终态。
- 自动录像在开组前完成相机准备，用户能看到真实画面并提前调整机位。
- 不录像仍不占用相机；主动录像恢复路径始终可达。
- 异常提前结束的可播放片段被诚实保留，不再冒充完整成功或被无条件删除。
- 系统中断、前后台与媒体服务重置拥有确定性恢复边界。

### 成本与限制

- Capture Session 需要显式状态机、generation 隔离、分阶段 deadline 和更多恢复测试。
- permission 等待与 machine timeout 必须分开处理，不能用一个简单 async timeout 包住全部阶段。
- Simulator 只能验证状态投影和纯逻辑；绿色相机指示、真实 Delegate、connection active、系统中断和
  录像可播放性仍必须由真机确认。

## 验证

- 单元测试覆盖准备阶段永久不返回、deadline 后迟到完成、同 Session 新 request 重试、无有效连接、
  interruption/foreground 恢复与单终态。
- Coordinator/UI 测试覆盖自动策略 preflight、不录像不启动、跨阶段手动排队、无目标反馈、暂停原因
  跨 View 重建保持，以及 starting/ready/unavailable 的可访问状态。
- 媒体终态测试覆盖正常用户停止、异常提前停止保留 `savedPartial`、success key 不越权升格、重复
  finish/stop 单 Alert 和无效临时文件清理。
- 运行 `make check` 与 `make verify`；自动化通过不能替代真机验收。
- 真机依次验证首次授权、正常自动/手动录像、拒绝后去设置恢复、快速前后台、锁屏、中断结束、
  连续 retry、低存储和 `.both` 独立片段。验收完成前不得声称真实录像故障已关闭。

## 参考

- [Apple: Setting up a capture session](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)
- [Apple: AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
- [Apple: AVCam—Building a camera app](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)
