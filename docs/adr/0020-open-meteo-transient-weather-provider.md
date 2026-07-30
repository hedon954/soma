# ADR 0020：使用 Open-Meteo 提供临时天气上下文

- 状态：已采纳
- 日期：2026-07-30
- 部分替代：[ADR 0017](0017-location-and-weather-context.md) 的 WeatherKit Provider 决策

## 背景

ADR 0017 选择 WeatherKit 为户外活动提供临时天气风险上下文，但 WeatherKit capability
要求付费 Apple Developer Program。Soma 当前使用 Personal Team 做连线真机开发，加入
WeatherKit entitlement 后无法生成 provisioning profile，也无法安装真机版本。

天气仍然只需要体感温度、湿度、降水和紫外线等少量当前条件。Open-Meteo 提供无需 API Key
的 HTTPS JSON API，非商业免费端点可以满足当前私人、无广告、无订阅阶段的低频调用。

切换第三方天气源会形成新的远程数据流：服务方能看到请求 IP 和请求中的坐标，其条款说明
故障排查日志可能保留坐标最多 90 天。这个边界必须由产品和用户界面明确说明，不能因为接口
免费而隐藏。

## 决策

1. `WeatherContextProvider` 保持本地受控入口，具体当前天气由可替换的
   `CurrentWeatherLoading` 实现获取；首个实现使用 Open-Meteo Forecast API。
2. 只有消息包含天气或户外活动语义，且该 Turn 已有用户授权获得的位置快照时才请求天气。
3. 请求前把经纬度四舍五入到小数点后两位，约为公里级位置；只请求当前体感温度、相对湿度、
   降水量和紫外线指数，不发送用户文字、场馆名称、媒体或健康数据。
4. 请求使用 ephemeral `URLSession`、三秒超时、不主动重试、不持久化 HTTP 缓存。原始
   JSON 和天气数值只在当前 Attempt 的内存中存在。
5. 风险阈值继续由本地确定性规则派生。远程 Agent 最多接收中文的一般风险提示，不接收坐标
   或原始天气值。
6. 服务不可用、响应缺字段或解析失败时返回空天气上下文，不阻塞 Agent，也不影响足迹成功
   资格。
7. 在隐私设置披露 Open-Meteo 会接收公里级坐标和 IP，在关于页与第三方声明提供
   “Weather data by Open-Meteo.com” 归属链接。
8. 当前只使用 Open-Meteo 非商业免费端点。Soma 增加订阅、广告或商业分发前，必须切换到
   合法的商业端点、恢复 WeatherKit，或新增 ADR 选择其他可商用方案。

## 未选择的方案

- 继续使用 WeatherKit：与当前 Personal Team 真机签名不兼容；加入付费 Apple Developer
  Program 后仍可重新评估。
- 在 iOS 客户端内保存带密钥的天气服务凭据：客户端无法可靠保密，会扩大密钥泄漏面。
- 增加代理服务器隐藏设备 IP：会引入账户外的常驻后端、运维和新的数据处理者，不符合当前
  本地优先范围。
- 使用 MET Norway 直连：要求可联系的 User-Agent，并建议移动应用通过缓存代理访问，当前
  集成成本和隐私边界更大。
- 永久缓存或保存天气：会形成历史天气数据库，超出本次 Agent 建议所需。

## 结果

### 正向影响

- Personal Team 可以继续构建、签名和安装真机版本。
- 不需要 API Key，天气失败仍保持非阻塞。
- 网络请求和模型输入都限制到当前任务所需的最少数据。

### 成本与限制

- Open-Meteo 免费端点无 SLA，且只允许非商业使用。
- Open-Meteo 会看到设备 IP 和公里级坐标，日志可能保留最多 90 天。
- 天气质量、可用性和服务条款由第三方控制，需要在商业发布前重新审查。

## 验证

- 单元测试覆盖相关语义门禁、坐标降精度、请求字段、JSON 解析、风险阈值和失败降级。
- `make verify` 通过。
- Personal Team 真机能够安装；位置关闭时无天气请求，相关户外文本在服务失败时仍能完成
  Agent。

## 参考

- [Open-Meteo Forecast API](https://open-meteo.com/en/docs)
- [Open-Meteo Pricing](https://open-meteo.com/en/pricing)
- [Open-Meteo Terms & Privacy](https://open-meteo.com/en/terms)
- [Open-Meteo Licence](https://open-meteo.com/en/licence)
- [Apple WeatherKit](https://developer.apple.com/weatherkit/)
