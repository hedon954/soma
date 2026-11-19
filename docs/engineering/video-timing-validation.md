# 训练视频时序验收

[PRD 082](../prd/082-coach-progress-reliability.md) 要求按完整视频识别动作阶段，并在遮挡时说明无法观察的时间范围。以下样片为程序绘制的虚构人物，不采集相机素材。视频和标注生成到本机临时目录。

```bash
xcrun swift scripts/build-video-timing-fixtures.swift /tmp/soma-video-timing
```

样片共 20 段，每秒 30 帧。覆盖深蹲、弯举、俯卧撑和过顶推举，以及快节奏、慢节奏、短重复、暂停、遮挡、混合动作和无动作。`ground-truth.json` 由绘制时使用的时间线生成，只供判分。暂停场景的转折点以第一次到达极点的时刻为准。

## 采集实际模型输出

开始前在「LLM 配置」确认所选模型显示「支持完整视频输入」。本机在发送时如缺少能力证据，只使用已配置的凭据查询其模型目录，请求不含附件或聊天内容。目录能力信息缓存于本机，模型目录不明确时保留原视频并提示更换。远程模式检查部署的完整视频能力。

已核对 OpenRouter 公开目录返回的 `architecture.input_modalities` 包含 `video`，且其聊天接口文档接受 `video_url`。这一证据只覆盖能力识别和请求格式。模型能否看清快速动作由下述样片实测决定。[OpenRouter 模型目录](https://openrouter.ai/docs/api/api-reference/models/get-models)、[聊天接口](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request)。

通过 Soma 已配置的提供方逐段发送完整 MP4。每段在独立的新会话中提问，避免其他样片的信息进入上下文。可以使用同一句话「看这段训练视频，按先后说出每次动作的开始、极点和结束时间。请用秒表示，说明遮挡或无法确认的时间范围。没有重复动作时请明确说明。」

记录 App 构建、提供方和模型版本、每段文件大小、完成用时，以及发送是否使用完整视频。将模型明确给出的时间抄入预测文件。模糊描述保持缺失。保留原始回答以便核对人工转换。

预测文件是按文件名标记的 JSON 数组。下例只演示字段格式。

```json
[
  {
    "clip": "clip-01.mp4",
    "events": [
      { "exercise": "squat", "phase": "rep_start", "seconds": 0.6 },
      { "exercise": "squat", "phase": "direction_change", "seconds": 1.6 },
      { "exercise": "squat", "phase": "rep_finish", "seconds": 2.8 }
    ],
    "occlusions": []
  }
]
```

动作名使用 `squat`、`curl`、`push_up`、`overhead_press`。阶段按模型的报告顺序记录。遮挡使用相对视频起点的 `start` 和 `end` 秒数。没有观察到动作或遮挡的片段也保留文件名并填空数组。

## 评分

```bash
ruby scripts/score-video-timing.rb /tmp/soma-video-timing/ground-truth.json /tmp/soma-video-timing/predictions.json
```

每个阶段要求动作与阶段名称匹配，时间差在 1 秒以内。同一预测只匹配一次，并按动作先后顺序配对。输出逐段结果、关键阶段召回、匹配时间戳的中位绝对误差、无动作时的误报和遮挡覆盖。

覆盖全部样片，关键阶段召回至少 90%，中位绝对误差不超过 0.5 秒，无动作和遮挡期间无误报，且每段标注遮挡与报告区间的交集占并集至少 50% 时通过。退出码 0 表示通过，1 表示未通过，2 表示输入数据有误。

这组材料用于验证完整视频路径和时间判断。器械分类、真实拍摄的视角与细微动作反馈需要另外用授权实拍样片抽验。
