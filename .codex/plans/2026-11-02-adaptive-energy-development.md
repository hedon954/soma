# Soma 动态消耗开发与发布计划

- 目标：完整实施消耗体系，发布新的 GitHub Release，覆盖安装到 hedon 的 iPhone 17 Pro Max。
- 依据：[研究方案](../../docs/research/2026-11-02-soma-energy-expenditure-system.md)、[PRD 076](../../docs/prd/076-adaptive-energy-system.md)、[ADR 0145](../../docs/adr/0145-adaptive-energy-system.md)。
- 发布前不将组件测试、模拟数据或设备安装元数据宣称为真实个人消耗准确度验证。

## 实施顺序

- [x] 确定性每日模型、参考日建立/换锚、训练口径与去重，先补原系数消失回归。
- [x] 28 天校准、留周敏感性、每周小步控制、独立留出模拟验证和启动门禁。
- [x] 本地事实/参考/每日快照/评估历史持久化，旧数据兼容、完整性、回滚和幂等。
- [x] 最小 HKWorkout 读取、训练区间外统计、来源与同步取消；每日记录继续覆盖。
- [x] 聊天采集生活事实和每日完整性；编辑/删除、暂停/恢复和审查历史；双端 Tool Schema。
- [x] 日周月年统一新投影、完整饮食缺口、习惯水平/预测，浅深主题交互验收。
- [ ] make verify，发布窗口归档与收口、版本/构建号、分逻辑提交、annotated tag 和 GitHub 工作流。
- [ ] make install-device 指定 iPhone 17 Pro Max；读取安装 bundle/version/build 核验，保留个人数据且不自动启动。

## 当前证据

2026-11-02：当前版本 0.0.27/build 31；此前 HealthKit 工作在同一工作树未提交。手机 hedon（iPhone18,2）处于 available。

### 已验证的组件

- EnergyDayCalculator：参考日差额、毛/净转换、显式身份去重、重叠待确认、未知区间暂停步行修正、换锚连续、可编码证据。
- EnergyReferenceBuilder：明确生活事实初值、完整时间预算、14 日至少 10 日参考与 7 日配对步幅、28 日习惯系数覆盖门槛。
- EnergyCalibration：28 天完整性、体重配对中位斜率及留周敏感性、两周同向、小步/限幅/累计上限、同输入不重复生效。
- EnergyContextEntry / EnergyEvidenceEntry：新增独立表、显式事实与私有推导分开、递增 revision 与前驱、同输入不新增、内部回滚/备份过滤、清空与演示隔离。
- 27 个新增 XCTest：每日计算 11、校准 7、参考 5、存储 4。make verify 通过：926 个 XCTest、8 个 Swift Testing，构建和静态门禁通过。首轮完整回归发现空新表与旧快照 nil 差异，已修复并重跑完整门禁通过。
- 没有接入运行时投影、聊天或新训练读取，当前手机上的系数问题尚未宣称修复；未提交、未发布、未安装。

### 紧接着做

1. 增加独立留出轨迹验证、磁盘旧库兼容与新存储边界验证；补齐生产投影的系数消失回归。
2. HKWorkout 最小读取 + 非训练时段统计，接入根同步的 generation 取消与私有证据；再集成每日投影。
3. 聊天事实/完整性固定 Tool 与双端 Schema；能量依据中的事实 CRUD、学习暂停/恢复与逐次历史。
4. 完成所有投影/隐私/交互验证后才提交发布、更新文档窗口和安装指定手机。

适配器核验：Apple DTS 在 https://developer.apple.com/forums/thread/759709 说明统计查询会合并重复步数；不要手工相加原样本。SDK HKWorkout.h 确认 statisticsForType: 从 iOS 16 可用，nil 表示没有关联样本；不能用已弃用 totalEnergyBurned 冒充已知净能量。区间边界穿越的数量样本不能随意按比例分摊，必须保留歧义或暂停校准。当前权限仍只包含三种日汇总，尚未扩展。

### 2026-11-03 运行时落地

- HealthKitDailyActivityReader 增加最小 HKWorkout 只读类型，读取身份/类型/来源/起止与关联活动能量。未用 deprecated totalEnergyBurned。训练时段并集外统计，严格边界与穿界样本标记；跨日训练未猜测分摊能量。私有依据批量覆盖到 EnergyEvidenceEntry.healthActivity，不新增公开训练记录。
- 连接文件从 byte 1 兼容为已连接、未请求新权限；再次点击“允许读取训练”请求 OS 权限后写 byte 2。仅表示请求流程结束，不声称读取获准。仍无静息、心率、路线、睡眠权限。
- EnergyRuntimeProjection 与 ProgressHistoryLoader 已接入统一投影：有限 56 日回看、生活初值、参考距离、设备净活动训练、步行差额与每周校准。日周月年/推荐目标共享该投影。根 EnergyRefreshCoordinator 在前台与相关事实保存后自动重算，不依赖进展；generation/取消拒绝切空间后的迟到写入。
- EnergyRuntimePersistence 批量保存参考、每日快照与校准，重复输入不保存。快照新增版本、静息公式、体重来源身份/日期；校准冻结 28 日输入、每日计算与摄入引用、前次评估指纹。
- 能量依据展示真实组件与有效系数，删除数字系数选择表单；系数历史按 50 条分页，可看采用/未采用理由、暂停学习和恢复旧修正。暂停状态使用固定 control:energy-learning 行，跨时区不改变开关含义。
- 当前未结束日只给超过全天参考的已观察步行正增量，不因上午少步而扣全天预算。无覆盖依据或训练区间未排除则保持参考。
- 关系读取已改为受限日期/身份查询及 256 分页；静态门禁计数更新为 3 种原始记录 + 上下文 + 私有依据 5 个有界日期查询，保留禁止根 View 查询和关系遍历的限制。
- 验证：最新 make verify 全部通过，940 个 XCTest、8 个 Swift Testing；新增运行时四周期系数回归、穿界/跨日统计、根自动计算/切空间、跨时区暂停以及独立未来活动变化/漏食/水重/体重假设分歧模拟。日志 /tmp/soma-energy-runtime-verify.log，结果 build/Soma-test.xcresult。没有声称这些模拟证明个人生理准确度。
- 尚未提交/发布/真机安装；新历史 UI 尚未做宿主实机/模拟器交互视觉验收。

### 接下来必须完成的完整范围

1. 聊天固定 Tool 与双端 Schema：工作坐/站/走、工时/通勤/家务事实，按日或用户明确日期范围确认饮食、训练、携带完整性；只返回用户事实，不给模型健康推导。事实审查、编辑和删除。
2. 热量口径：当前旧 WorkoutEntry 只有 calorieMET，用户提供 calories 也可能保留该 MET（ConversationRecorderRecords.swift 创建路径）。需要明确持久 scope/source，用户值未知口径不得冒充 MET 毛能量；旧资料保持审慎解释，新增/编辑/DTO/Schema/测试同步。
3. 训练关联 GUI 与持久依据：COROS 与 Soma 同场目前会被标为重叠并暂不计入，不能自动猜关联。需要本地明确关联/解除，并先正确聚合 Session 的多个动作再与设备整场去重，不能把多个动作当重复后只留一个。关联含健康身份，不能进入模型或备份。
4. 完整记食门槛：ProgressDailyMetrics 已有 foodConfirmedComplete，但 ProgressEnergyDeficit 仍按旧“有餐食”计算。改为已结束日正式累计必须完整；当天展示清楚的记录差额。补回归与 UI 文案。
5. 习惯水平/有明确标记的预测仍需完成生产接入，已完成训练必须替换预测，休息日不重复奖励。
6. 增加新表的磁盘旧库兼容测试、私有训练更新/取消回归、暂停/恢复回归及实际双主题/大字号/键盘/滚动验收。LocalEnergyTraining 已改为 session/performance/set 的有界标识查询；不要恢复关系遍历。
7. 所有变更完成后统一校对 PRD/ADR/CLAUDE/验收和数据库文档（075/0144 仍有局部措辞需收口）；更新新版本与递增构建号，按文档窗口归档/合并收口。拆逻辑提交，annotated tag、push、核验 CI 与 GitHub Release，再指定 hedon iPhone 17 Pro Max 安装并核对 bundle/version/build。不要现在发布这份仍缺聊天/关联/完整性闭环的中间状态。

### 2026-11-03 完整链路与发布收口

- 已接入 record_energy_context 固定 Tool 与双端 Schema，明确生活/工时/通勤/家务/逐日完整性；事实可编辑、删除与重新确认。新日期部分生活事实继承此前明确的未变事实；缺失不猜测。
- 饮食完整性绑定餐食身份/日期/热量/缺项指纹，变动后失效；当天仅显示已记饮食差额，正式累计排除未确认日，空餐食不补零。
- WorkoutEntry.calorieScopeRaw 兼容新增；本地 MET、用户活动、含静息和未知分开。旧 MET 不证明旧值来源，非热量修改保留用户原值。双端 calories_scope 与 DTO/导出同步。
- Soma 同一 Session 全部动作先合计净能量；一对一明确训练关联保存在私有 association 修订中，健康设备有效活动能量优先，缺能量回退整场。不同来源未知区间不重复累计。关联后的区间覆盖检查只用被采用的一份训练。
- 根前台重算、每周校准、历史恢复/暂停、来源失败保留与切空间拒绝迟到写入均已接入。近期习惯 ΣT/ΣR 与未来七日计划/同星期预测已生产接入，预测不计实际缺口和校准。
- 历史展示旧/新系数、中间量、算法、生效日期与冻结的 28 日逐日依据，可回看原餐食。完善生活按钮复用真正的教练发送路径并清除之前快捷限制。
- 新表磁盘旧库兼容通过，原 UUID/日期/备注/热量保留，旧 scope nil；新表写入并重开成功。实际完整 make verify 已通过 964 XCTest + 8 Swift Testing；之后新补日活动不计训练天数/不阻止计划过期的回归，待最终发布门禁确认。
- UI：iPhone 17 Pro 浅/深完整关联、编辑保存、暂停；Accessibility XXXL 键盘/滚动；iPhone 16e 小屏；iPad 11 寸大字号均通过并已检查虚构截图。校准历史下钻测试通过。三项日运动记录双主题和大字号/设置测试通过。日志 /tmp/soma-energy-ui-final.log、/tmp/soma-energy-ui-history.log、/tmp/soma-energy-ui-small.log、/tmp/soma-energy-ui-ipad.log、/tmp/soma-daily-activity-ui-final.log；17 Pro/小屏/iPad xcresult 另存 /tmp/soma-energy-ui-*-accepted.xcresult。
- GitHub 最新核验 v0.0.27，准备 v0.0.28/build 32。已更新版本与 Changelog，已将 PRD 068 原文 git mv 到 archive/0.0.25 并把仍有效 Session 准备页边界合并进压缩起点，更新互链及目录索引。尚未提交、push、tag、Release 或安装。
- make online-check 仍被既存 iOS 直连反馈凭据阻断；GitHub 只发源码，个人手机覆盖安装，不能宣称 TestFlight/App Store 已发布。
- 实时手机 hedon iPhone17ProMax iPhone18,2，CoreDevice <本地设备标识> available/paired，unlockedSinceBoot=true、passcodeRequired=true。待构建签名时重新核验 Team 和 UDID，不自动启动。

### 剩余交付步骤

1. 最后审查并运行发布版本完整 make verify（含刚补的日活动与计划回归）；保存 UI 附件后避免结果覆盖。
2. 按可审查逻辑拆提交：纯模型/算法；持久化与只读健康基础；聊天/运行时/UI 集成；发布文档和版本归档。新纯 EnergyInputCoding 与 WorkoutCalorieScope 已与持久化扩展拆文件，方便独立提交。
3. 审核最终差异和无真实健康/凭据，Conventional 中文提交，scripts/verify-release.sh v0.0.28，annotated tag，push，等待 CI/Release 成功，读取正式发布元数据。
4. 指定 iPhone 17 Pro Max make install-device，查询已安装 top.hedon.soma 的 version/build；保留个人库、不自动启动。所有这些完成之前目标保持 active。

发布门禁：v0.0.28/build 32 的 make verify 全部通过，965 XCTest、8 Swift Testing，构建零警告。代码已按内核、健康持久化、产品集成分三次提交；发布元数据单独收口。签名团队与旧 App 一致且本机证书有效至 2027 年。开发磁盘挂载被手机锁定阻止，已请求维护者解锁；此状态不是安装成功。
