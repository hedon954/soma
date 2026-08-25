# ADR 0017：位置与天气作为受控的 Turn 上下文

- 状态：部分已替代
- 日期：2026-07-30
- 关联：[ADR 0001](0001-local-first-dual-data-spaces.md)
- 后续替代：[ADR 0020](0020-open-meteo-transient-weather-provider.md) 替代 WeatherKit Provider

## 背景

位置能补充个人足迹，并在用户忘记切换健身房时提供更准确的场馆上下文；WeatherKit 可以
在户外活动时辅助强度与生活建议。但精确位置属于敏感数据，天气数据还受服务授权、归属和
存储条款约束，不能被当作常驻 Agent 工具或历史数据库。

## 决策

- 位置默认关闭，由用户从聊天或隐私设置主动开启。
- 只申请前台 `When In Use` 权限，并在每次发送时调用一次性定位。
- 不启用后台定位、持续更新、地理围栏或“始终允许”权限。
- 定位结果保存为当前数据空间内的 `LocationSnapshot`；足迹展示语义位置，原始坐标不进入
  远程请求。
- 地址解析在 iOS 26 及以上使用 MapKit reverse geocoding，旧系统使用 Core Location
  兼容路径；解析失败时仍保留坐标和精度事实。
- 健身房可以由用户明确绑定当前位置。唯一空间命中只影响本次 Turn 的 `effectiveGymID`，
  不改变 `GymProfile.isCurrent`。
- WeatherKit 只由本地 `WeatherContextProvider` 在明确相关的文本中按需调用。
- WeatherKit 原始值不持久化；App 只在内存中生成最小、非诊断的运动风险提示。
- 天气服务不可用时直接降级，不阻塞 Agent，也不改变足迹成功资格。

## 数据流

```text
用户开启位置
  → 发送时 requestLocation
  → 本地 LocationSnapshot
      ├─ 足迹语义位置
      ├─ 本地确定性健身房匹配
      └─ 相关时临时调用 WeatherKit → 派生风险提示 → Agent
```

远程模型最多接收语义位置、本次健身房和派生风险提示；不接收经纬度、水平精度或 WeatherKit
原始负载。

## 未选择的方案

- App 启动时申请定位：缺少当下用途，干扰且难以建立信任。
- 持续或后台跟踪：超出个人足迹所需的最小权限。
- 根据位置静默切换全局健身房：室内精度和同楼场馆会造成错误状态。
- 把位置与 WeatherKit 暴露成模型可任意调用的 Tool：扩大权限与远程数据边界。
- 永久保存天气快照：会形成历史天气数据库并扩大授权合规风险。

## 结果

- 位置是可选、一次性、可删除的用户事实。
- 场馆判断是本地确定性能力，Agent 只消费结果。
- 天气是临时增强，不成为足迹或 Trace 的长期数据源。

## 参考

- [Apple：Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [Apple：CLLocationManager.requestLocation](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation())
- [Apple：MKReverseGeocodingRequest](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest)
- [Apple：WeatherKit](https://developer.apple.com/documentation/weatherkit)
- [Apple：WeatherKit Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit)
- [Apple Developer Program License Agreement，Attachment 8](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
