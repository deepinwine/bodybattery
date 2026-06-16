# BodyBattery

一个本地优先、省电的"身体电量"App，从 Apple 健康读取数据并在 iPhone 上计算，
把轻量快照同步给 Apple Watch 展示。不联网、不上传、不轮询。

## 架构

```
Apple 健康 ──► iPhone (计算) ──WatchConnectivity──► Apple Watch (只显示)
```

- **iPhone 端**负责读取 HealthKit 并计算身体电量。只在 App 打开（带防抖冷却）或
  用户点击"刷新健康数据"时执行，没有后台 Timer、没有 HKObserverQuery、没有轮询。
- **Apple Watch 端**不读取 HealthKit，只接收并展示 iPhone 发来的快照，通过
  `updateApplicationContext` 保底交付，慢变量不需要实时唤醒。
- **Shared（BodyBatteryShared framework）**是纯算法与编解码层
  （`BodyBatteryCalculator`、`BatterySnapshotCodec`、`BatteryLevelStyle`），
  可被三端和测试 target 共用。

## 身体电量模型

`BodyBatteryCalculator.summarize(_:)` 是确定性、常数时间的纯函数，输入是预聚合标量
（不遍历原始样本），输出包含电量主值及压力 / 恢复 / 消耗 / 日耗 / 疲劳负荷 / 睡眠质量
等子分。模型要点：

- **晨间起点**由睡眠时长、睡眠质量、HRV、恢复分共同决定，再按个人基线做增减。
- **日内消耗**综合清醒时长（从起床算起）、今日步数 / 活动能量 / 静息能量。
- **个人基线**取最近 7 天的滚动均值，让"高于/低于你平时"的偏离才有意义，而不是
  对所有人都用同一把尺子。
- **疲劳负荷**用最近 7 天加权活动量（越近权重越高）累计，连续高强度训练日会压低电量。

## 功能

- 今日：电量圆环 + 压力 / 恢复 / 日耗 / 疲劳 / 睡眠 / HRV / 能量指标网格 + 今日消耗。
- 活动：最近 30 天每日步数 / 活动能量 / 电量三环。
- 趋势：7 / 30 / 60 天电量、压力、日耗、睡眠多折线 + 均值 / 低点 / 最高压力摘要。
- 首次启动 onboarding：用户画像、心率区间估算、可编辑健康目标、通知与健康权限授权。
- 本地保存最近 60 天同步记录（AppStorage JSON），用于趋势与活动页。

## 构建

需要 Xcode 16+，iOS 18+ / watchOS 11+。

```bash
# 构建 iPhone + 嵌入 Watch app（需要已安装对应 watchOS Simulator runtime）
xcodebuild build -project BodyBattery.xcodeproj -scheme BodyBattery \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO

# 只跑共享框架 + 单元测试（不依赖 Watch/iOS app）
xcodebuild test -project BodyBattery.xcodeproj -scheme BodyBatteryShared \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

## Target 说明

| Target | 产物 | 说明 |
| --- | --- | --- |
| `BodyBatteryiOS` | iOS App | HealthKit 读取、电量计算、趋势/onboarding/主界面 |
| `BodyBatteryWatchApp` | watchOS App | 只接收并展示 iPhone 快照 |
| `BodyBatteryShared` | Framework | 纯算法与 WatchConnectivity 编解码 |
| `BodyBatteryTests` | Unit Tests | 算法、序列化、clamp 边界测试 |

## 隐私

所有计算在本地完成，App 不包含任何网络请求，不上传任何健康数据。
Watch 与 iPhone 之间仅通过系统的 WatchConnectivity 传输聚合后的标量快照。
