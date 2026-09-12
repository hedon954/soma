# 训练分享海报落地

- 视觉目标：维护者选定的白底黑字、橙黄色主视觉、大号窄体容量，右侧前后肌群图，底部三列统计和单行明细。固定纸面外观，分享弹层适配双主题。
- 成功路径：日训练和带练完成复用同一海报；动作名和摘要优先同排，长内容完整换行；连续同值逻辑组压缩，不截断异构明细。
- 数据真值：未知重量保持未知，零才是自重；保留不同重量、次数、时长、侧别、组类型、部分完成与失败信息；不改存储、容量/热量计算或远程数据流。
- 失败路径：保留本机渲染重试、相册权限提示、关闭与系统分享。
- 实现：共享 WorkoutRecordDraft.displayRuns；海报专用配色与 MuscleMapView.poster 模式，不改变普通肌群图。
- 决策：[ADR 0000](../../docs/adr/0000-origin-through-0.0.11.md)。
- 验证：摘要回归、固定纸面深浅外观像素一致、长中文和缺失值；make format/check/verify；标准/小屏 iPhone 与 iPad 上的分享、滚动、安全区和大字号；真机安装后手动启动。
- 视觉证据与差异结论：根目录 design-qa.md；截图存于本机 build/share-qa/。
- 提交边界：排除另一任务的 Soma/Services/Settings/PerformanceTestFixture.swift。
- Release 的 macos-26 / Xcode 26.6 和安装后手动启动已分别提交 56a5d2f、15081de 并推送；不新增 tag 或发布版本。
