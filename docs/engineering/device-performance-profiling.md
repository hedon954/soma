# 真机性能录制：一次安装，多次复用

- 上游依据：[2026-08-25 性能优化收尾与踩坑报告](performance-optimization-retrospective-2026-08-25.md)

本协议是 Soma 真机性能录制的唯一入口。目标是把“构建/安装”和“录制/分析”彻底分开，避免
XCUITest Runner、进程发现竞态、锁屏和空 Trace 反复浪费时间。

## 首次或产品代码变化后：安装一次

```bash
DEVELOPMENT_TEAM=你的TeamID \
SOMA_DEVICE_ID=设备ID \
SOMA_DEVICE_CONFIGURATION=Release \
make install-device
```

安装脚本成功写入真机后，会记录 App 产品输入指纹、版本、构建号和本地二进制 UUID。指纹只包含
`project.yml`、App/Widget 源码与资源、依赖锁文件和 Xcode 版本；文档、测试及 profiling 脚本变化
不会让已安装 Release 失效。

## 后续录制：直接复用

```bash
SOMA_PROFILE_DEVICE=设备ID make perf-profile-device
```

默认场景为一条 18 KB 的 Markdown 长流回复、流完成后 1 秒开始、10 轮共 40 次 Tab 切换、
75 秒 Time Profiler。脚本会明确打印 `no build or install will run`，并完成：

1. 解析 CoreDevice 与 xctrace 两套设备 ID，检查连接和解锁状态；
2. 比较当前产品指纹、安装 stamp、设备上版本和构建号；不一致时快速失败，只提示重新安装一次；
3. 以环境变量启动内存数据库和虚构性能夹具，不接触个人数据库；
4. 连续两次确认同一 App PID，正式 Trace 直接精确 attach 这个 PID，不额外录制会干扰
   Instruments 会话的短 Trace；
5. 正式 attach 尚未开始就失败时，只重置一次 Xcode Instruments helper 并重试；xctrace 15 秒
   未真正启动即终止，已经开始录制后的失败绝不自动重跑；
6. App 等待夹具明确进入 `completed`，而不是用宿主机固定 sleep 猜测流结束；
7. 导出 TOC、os_signpost XML、机器可读 JSON 和 manifest，并强制校验样本数及 p95 预算。

每次运行写入独立的 `run-<timestamp>-<pid>/record-attempt-<n>` 目录，不覆盖旧证据。
`record_failed`、`record_failed_after_start`、`start_timed_out`、`timed_out`、
`invalid_trace`、`signpost_export_failed` 和
`analysis_failed` 是不同结论，任何一种都不能冒充性能通过。

## 常用覆盖参数

```bash
SOMA_PROFILE_DEVICE=设备ID \
SOMA_PROFILE_INTERACTION_ROUNDS=30 \
SOMA_PROFILE_DURATION=90s \
SOMA_PROFILE_TAB_P95_BUDGET_MS=100 \
make perf-profile-device
```

`SOMA_PROFILE_INTERACTION_ROUNDS` 是单个 Trace 内的交互轮数。为保证每份 Trace 都从全新的内存夹具
和 App 进程开始，canonical harness 强制 `SOMA_PROFILE_RUNS=1` 且每次只接受一个 Instruments
template；需要 Time Profiler、SwiftUI 和 Animation Hitches 时分别执行三次同一命令，三次都复用同一
已安装 Release，不会重新构建。正式结论至少使用 10 轮，发布级证据建议 30 轮。

## 禁止路径

- 不直接运行物理设备 `SomaUITests-Runner`；当前设备上存在已确认的 code 74 启动故障。
- 不在 profiling 命令里调用 `xcodebuild`、重新签名或安装。
- 不按进程名猜 attach 目标；只使用本次启动后稳定的精确 PID。
- 不把 App 安装成功、启动成功、Trace 文件存在或 Simulator 结果当作真机交互预算通过。

旧入口 `scripts/profile-device-tab-loop.sh` 只转发到本协议的 canonical harness，不再维护第二套实现。
