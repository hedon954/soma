# Brand assets

## COROS logo

- Source: [https://www.coros.com/public/images/COROS.svg](https://www.coros.com/public/images/COROS.svg) (downloaded 2026-11-05)
- Bundled as `Assets.xcassets/CorosLogo.imageset` (PNG 1x/2x/3x rendered from that SVG)
- COROS and the COROS logo are trademarks of COROS Wearables Inc. Used only to label COROS as a HealthKit data source inside Soma; not affiliated with or endorsed by COROS.

## Keep App Store icon（官方发行页图标，非自绘）

- **Source page:** [Keep - AI 运动教练 · App Store (CN)](https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580) (Apple App Store listing; developer Keep / Beijing Calorie Technology Co., Ltd.; bundle `com.gotokeep.keep`; Adam ID `952694580`)
- **Asset URL (retrieved 2026-11-09 via Apple iTunes Lookup `https://itunes.apple.com/lookup?id=952694580&country=cn` → `artworkUrl512`, then resized):**
  - `https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/77/97/81/77978107-2fd8-b279-ac4c-8c2123ac1e08/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/1024x1024bb.jpg`
- Bundled as `Assets.xcassets/KeepLogo.imageset` (PNG 60/120/180 from that artwork). Rendered with **original** colors; not templated, tinted, or redrawn.
- **Attribution / license posture:** Keep and related marks are trademarks of their owners. Soma does **not** claim an open license, trademark license, or endorsement. The icon is used only to recognize Keep as a HealthKit `HKSource` in-list. If Apple/Keep require removal, delete this imageset and fall back to a generic SF Symbol + the name “Keep”.
- Matched when HealthKit `source.name` / `bundleIdentifier` indicate Keep (e.g. name `Keep`, bundle contains `gotokeep`).
