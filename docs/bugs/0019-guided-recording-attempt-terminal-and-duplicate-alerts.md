# BUG 0019：录像提前终结后成功误判并重复提示失败

- 状态：首次修复不足；attempt 去重继续有效，完整 activation 与部分证据由 BUG 0020 继续修复
- 发现日期：2026-08-16
- 影响范围：计划带练自动/手动录像、视频文件保留、失败提示与后续训练
- 修订自：[BUG 0013](0013-guided-recording-startup-silent-stall.md) 的启动截止与独立失败事件修复
- 后续修订：[BUG 0020](0020-guided-camera-activation-deadline-and-partial-evidence.md) 把 attempt 起点前移到相机准备之前，并区分系统提前终止后保留的部分文件与完整成功
- 下游落地：
  - [PRD 031](../prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
  - [ADR 0073](../adr/0073-independent-set-prescriptions-efforts-and-guided-finalization.md)

## 症状

系统已经回调录像开始后，可能在用户完成当前组之前提前回调结束。界面先弹一次“录像无法继续”；
用户继续完成组或休息时又弹出第二次失败。部分系统返回同时包含 error 和“文件实际成功完成”标记，
现有实现仍把它当作失败并删除可能可用的视频。

截图中同一次训练先后出现“录像失败：已停止录制”和“系统录像已提前停止，未保存视频；训练数据
已保留”等提示，说明一次物理请求被多个 UI 状态源分别投影。

## 根因

BUG 0013 修复了“启动 Delegate 永不返回”和“相同错误重试无法再次提示”，但一次录像请求仍没有
稳定 attempt 身份和单一终态：

1. `didStartRecordingTo` 后 Coordinator 保存活动 Set；若系统随后自行 `didFinishRecordingTo`，
   Camera state 变化不会同步清除 Coordinator 的活动记录身份。
2. 用户完成组时，Coordinator 仍调用 stop；此时 Movie Output 已停止，服务再生成 `stop-missing`，
   形成同一物理失败的第二个错误。
3. 带练 View 同时监听 Coordinator failure、Camera unavailable 和 preview issue，三个来源都可以
   创建系统 Alert，缺少 attempt 级去重。
4. 文件结束处理仅检查 `error != nil`，没有读取 `AVErrorRecordingSuccessfullyFinishedKey` 和验证
   输出文件，因此会误删系统声明实际完成的视频。

## 修复

- 每次自动或手动录像建立唯一 attempt ID，并绑定目标 Effort。
- Camera adapter 将 started、saved、failed、cancelled 作为 attempt 事件返回；同一 attempt 只接受
  第一个终态。
- Delegate 提前结束、系统中断、后台和用户 stop 都通知 Coordinator 清除活动 attempt。
- `stopRecording` 对已终结 attempt 幂等，返回已有结果，不创建 `stop-missing`。
- `error == nil`，或成功完成 key 为 true 且输出文件有效时，按成功保留文件。
- Coordinator 是唯一用户警告投影源；Camera/preview 状态只驱动内联取景状态。
- 同一 attempt 最多弹一次；用户重试建立新 attempt，所以新的真实失败可以再次提示。
- 自动 attempt 失败后暂停后续自动录像，训练和训练事实继续；常驻录像按钮允许用户恢复。
- 日志只写 attempt、阶段、error domain/code、成功 key 和文件有效性布尔值，不写路径、动作或身体数据。

## 回归门禁

- start → Delegate 提前 finish → 用户完成 Effort：不再调用第二次物理 stop，不出现第二个 Alert。
- Delegate 提供非空 error 但成功 key 为 true 且文件有效：文件保留并绑定 Effort。
- 重复 finish/stop/cancel：同一 attempt 只产生一个终态和最多一个用户警告。
- 同一错误的新手动 retry 使用新 attempt，允许再次提示。
- 权限拒绝、启动超时、磁盘/编码失败和系统中断都不阻断训练状态与动作记录保存。
- 真机分别验证正常录像、快速前后台、来电/系统中断、连续重试和左右独立片段；绿色相机指示与
  文件可播放性不能由 Simulator 证明。

## 验证状态

- 自动化、`make check` 与 `make verify` 结果应在实现完成后填写，本文不预先声称通过。
- 维护者真机复验尚未完成；在此之前状态保持“修复中”或“已修复，待真机复验”。
