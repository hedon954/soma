# 2026-08-04：免费签名 Widget 降级

## 用户结果

未加入付费 Apple Developer Team 时，Soma 仍可在真机安装，并从主屏或锁屏一步进入文字、拍照、照片/视频记录。

## 边界

- 移除 App Group entitlement 和所有共享训练状态投影。
- 不以服务器或其他跨进程存储替代本地快照。
- 进行中带练、固定计划、训练节奏和组件隐私设置暂不显示；对应实现由 ADR 0042 暂缓。

## 关联

- [PRD 018](../prd/018-free-team-widget-fallback.md)
- [ADR 0043](../adr/0043-free-team-widget-fallback.md)
