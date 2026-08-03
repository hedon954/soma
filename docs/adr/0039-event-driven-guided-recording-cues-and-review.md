# ADR 0039：带练录像、语音与复盘由确定性事件驱动

- 状态：已采纳
- 日期：2026-08-04
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0030](0030-deterministic-guided-workout-and-session-recording.md) 的单一自动录像策略与每动作单段证据
  - [ADR 0038](0038-focused-guided-workout-and-capture-geometry.md) 的开始前相机校准与紧凑预览完整适配
- 后续替代：暂无
- 上游依据：
  - [PRD 014](../prd/014-guided-workout-recording-cues-and-review.md)
  - [带练录像策略、语音节奏、完成反馈与历史管理调研](../research/2026-08-04-guided-workout-recording-cues-and-review.md)
  - [BUG 0010](../bugs/0010-guided-recording-state-and-cue-gaps.md)

## 背景

现有 `AutoRecordingPolicy.enabled` 同时表达用户策略、相机准备和当前录像，导致 UI 与文件状态靠
计划规则反推。`startRecording` 调用后立即标记 `.recording`，没有等待系统确认写入开始；完成组时
再次调用 `shouldRecord` 判断是否停止，使手动录制和每组录制没有可靠生命周期。

语音只有一个命令式 `announce` 调用，没有把训练阶段、倒计时和休息时间建模为事件。训练总结
和删除又分别散落在 View，无法形成完整可恢复闭环。

## 决策

1. Session 的录像策略与实际录像活动分离：
   - `.disabled`：不自动录像；
   - `.enabled`：兼容旧数据并表示每动作首个目标工作组；
   - `.everySet`：每一组自动录像；
   - `.paused/.cancelled`：保留现有运行时控制语义。
2. 自动策略只决定某组开始时是否发起录像；当前录像由独立 `recordingSetID`/启动状态表达，停止
   和保存只读取实际活动，不再重新执行策略判断。
3. 任意 `.setInProgress` Set 都可显式手动录像；自动关闭或非目标组不会限制手动入口。
4. 相机采用 lazy activation：只有自动或手动请求录像时才 `prepare` Capture Session。开始页、
   动作介绍和无录像组不启动相机、不创建预览 Host。
5. `WorkoutCameraService` 等待 `AVCaptureFileOutputRecordingDelegate.didStartRecordingTo` 后才
   完成启动调用并投影 `.recording`；`didFinishRecordingTo` 是文件成功、失败与清理的唯一终点。
6. 录像证据归属 `WorkoutSet.recordedVideoPath`。`ExercisePerformance.activeVideoPath` 保留为旧数据
   和默认分析入口的兼容投影，不再限制同动作保存多段录像。
7. 紧凑预览 Host 使用 `.resizeAspectFill` 消除黑边；放大完整取景 Host 使用 `.resizeAspect` 保留
   完整画幅。二者继续共享同一 Capture Session、Movie Output 和 Preview Layer。
8. 语音由 `GuidedWorkoutCue` 事件生成，事件至少包含动作进入、组准备、倒计时、组开始、组完成、
   休息倒计时、下一动作、暂停/恢复和训练完成。事件包含稳定去重键，同键只执行一次。
9. 播报新阶段前停止已过期 utterance 队列；倒计时以持久 `phaseStartedAt`/`restTargetEndAt` 的绝对
   时间派生，View 重建不会重复或延迟累积播报。
10. 训练结束先进入本地确定性 `TrainingSessionReview` 投影；不自动调用模型。历史删除由
    `TrainingPlanStore.deleteSession` 统一级联 Performance、Set、Analysis 和私有录像。
11. 相机、语音或媒体删除失败必须显示可恢复错误，但不能回滚已经确认的训练事实。

## 未选择的方案

- 继续用自动录像策略判断当前是否正在录：无法覆盖手动、重试和每组录像。
- 开始页常驻校准预览：在用户还没录像时提前申请和占用相机，违反最小化使用。
- 所有预览统一 `resizeAspectFill`：放大态无法继续解释完整保存画幅。
- 每个动作只保留最后一段视频：会丢失“每一组都录”的证据归属。
- 用大模型生成每组语音或结束总结：引入网络、Token 和不可恢复延迟。
- View 直接删除 Session：当前 UUID 关联没有 SwiftData cascade，容易遗留孤儿模型与私有媒体。

## 结果

### 正向影响

- 不录像时完全不占用相机；自动与手动录像共享同一可靠状态机。
- UI 红点对应系统确认的真实写入，不再把请求或策略伪装成成功。
- 每组录像可独立查看、保留和随 Session 删除。
- 第一组、后续组、休息和完成拥有一致语音节奏。
- 结束反馈和历史清理形成确定性本地闭环。

### 成本与限制

- `WorkoutSet` 增加可选录像路径；旧 `ExercisePerformance.activeVideoPath` 在迁移期继续存在。
- 紧凑小窗为消除黑边允许裁切，不能称为“完整画幅”；放大态仍是真实边界。
- Simulator 无法证明真实录像回调、语音路由和系统相机指示，必须保留真机验收。
- 删除私有文件与 SwiftData 不是跨介质事务；实现先验证归属、删除模型并尽力回收文件，失败需可见。

## 验证

- 单元测试覆盖禁用/单组/每组/手动录像选择、实际活动停止、每 Set 路径与旧策略兼容。
- 录像服务测试覆盖“请求不等于开始”、启动回调、结束回调与失败状态。
- 语音计划测试覆盖每组 3/2/1、开始、休息、下一动作和完成，并验证去重键。
- Store 测试覆盖 Session 级联删除和媒体路径集合。
- 模拟器检查无录像/录像中、紧凑/放大、完成总结和左滑删除布局。
- 真机验证真实相机、语音、横竖屏、后台中断和多段视频播放。
