# PRD 035：带练先取景再录像，完成后立即分享并回训练主页

- 状态：已实施，待真机录像与分享验收
- 日期：2026-08-21
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的带练完成路径与训练 Tab 入口
  - [PRD 013](013-guided-workout-experience-and-capture.md) 的目标组开始时自动放大取景
  - [PRD 014](014-guided-workout-recording-cues-and-review.md) 的「未开始写文件不显示取景器」与倒计时归零即请求录像
  - [PRD 031](031-guided-workout-v5-independent-sets-and-automatic-completion.md) 的自动完成分享预览与结束后停留页
  - [PRD 034](034-history-media-tabs-and-guided-capture-polish.md) 的倒计时 PIP 宿主上先 `startRecording` 再进入 `.setInProgress`
- 后续修订：暂无
- 上游依据：
  - [BUG 0026](../bugs/0026-guided-auto-recording-still-stops-without-reason.md)
  - [ADR 0074](../adr/0074-bounded-guided-camera-activation-and-partial-evidence.md)
- 下游落地：[训练领域模型与运行时协议](../engineering/training-domain-model.md)

## 背景

v0.0.8 在真机上，自动录像（录第一组或每一组）仍会在开始后立刻关掉，且没有异常原因。
根因是开组瞬间同时换预览宿主（倒计时 PIP → 执行页小窗，甚至自动放大取景），AVFoundation
结束当前文件；成功 key 为 true 的极短片段被当成正常保存，所以界面像「自己停了」。

同时，计划全部结束后会先停在「本次训练已完成 / 查看分享」，关闭分享后又回到计划详情，
而不是训练 Tab 主页。

## 用户结果

1. 动作开始前只打开相机小窗取景；倒计时结束、动作正式开始时自动进入放大录制页并开始写文件。
2. 放大录制中可以收回到小窗，小窗继续录像；再点小窗可重新放大。
3. 「每个动作录第一组」时，后面组不再显示取景，也不占用相机。
4. 动作或该侧 Effort 结束后保存当前录像；训练事实继续可完成。
5. 异常提前结束必须弹出可理解原因，不能静默当成完整成功。
6. 带练计划执行结束（最后一组完成或提前结束）后立刻出现本地分享预览；关闭后回到训练主页。

## 产品规则

### 取景与录像时序

- 用户选择了自动录像后，动作介绍或组前倒计时做 camera-ready preflight；`.previewing` 即可
  见取景，红点只代表 `didStartRecordingTo`。
- 倒计时归零：若本组会录像，先进入 `.setInProgress` 并自动打开放大取景，等该宿主挂上后再
  `startRecording`。
- 进入 `.recording` 不再二次自动放大。用户可在录像中收起放大取景回到小窗，小窗继续写文件；
  点小窗可再放大。已有预览连接时换宿主只移动预览层，不拆除 RotationCoordinator，不重绑
  session；预览阶段的 `session-interruption` 不得停掉仍由带练持有的 Capture Session，
  `startRecording` 必须复用已在跑的 Session。
- 动作介绍、倒计时、休息和执行页小窗都默认贴在示范图／主画面右侧垂直居中，可按住拖动；同一固定竖屏 9:16 尺寸。
- 只有当前或下一即将开始的 Effort 是自动/预约录像目标时才显示取景。首组策略下后续组不预览、
  不保持 Capture Session。
- 组或 Effort 正常完成后 `stopRecording` 并绑定当前 Effort。
- 不录像策略下仍不申请、不启动相机。

### 失败

- 系统提前结束且文件可读时保留为部分证据，并弹出诊断原因。
- 同 attempt 只提示一次；训练继续，常驻录像可重试。

### 完成与分享

- 计划执行结束（最后一个 Effort 收口，或用户提前结束并保留已完成组）后直接呈现
  `WorkoutShareSheet`，不再把 `GuidedSessionReviewView` 当作必经页。
- 关闭分享预览后关闭带练全屏页，并从计划详情回到训练 Tab 根页。
- 系统分享仍需用户点「分享」。

## 数据与隐私

- 不新增 SwiftData 字段、远程数据流、权限或 Agent Tool。
- 录像与分享海报仍只留在本机；海报不含照片、视频帧或位置。

## 明确不在范围

- 改变三种录像策略语义、热量、容量或 attempt 终态模型。
- 自动计次、姿态识别或把录像上传到服务器。

## 验收

- 录第一组：倒计时小窗取景，开组后进入放大录制且出现红点；第 2 组起无预览。
- 动作介绍小窗默认贴在示范图右侧，可按住拖动；开组后若收起放大页，执行页小窗同样贴右可拖。
- 放大录制中可缩小到小窗且红点仍在；点小窗可再放大。异常停录弹出具体原因，诊断日志含调用栈。
- 执行页小窗与动作介绍同一 9:16 比例。
- 最后一组完成或提前结束后立刻出现分享预览；点关闭回到训练主页。
- `testAutomaticRecordingStartsAfterSetIsInProgress`、
  `testEnabledPolicyDoesNotRecordLaterSetsAndReleasesPreview`、
  `testEndEarlyAbandonsSessionWithoutRequiringRemainingSets`、
  `testSetStartExpandsCaptureAndCollapseSurvivesRecording` 覆盖时序；
  `validate-repository.sh` 守卫录像中不重建连接。真实相机仍需真机验收。
