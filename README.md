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
（不遍历原始样本），输出包含电量主值及压力 / 恢复 / 消耗 / 日耗 / 疲劳负荷 / 睡眠质量 /
自律平衡 / HRV 趋势等子分。

模型以 **Garmin / Firstbeat 公开方法学**为依据，核心是 **HRV 反映的自主神经平衡**：

- **自主神经平衡（autonomicBalance，0–100）** 是模型的中枢信号。把今日 HRV（Apple 健康
  提供的 SDNN）做对数变换 `ln(SDNN)`——这是 HRV 研究的标准归一化做法（HRV4Training 对
  RMSSD 用同样变换，SDNN 与之高度相关）——再相对个人 7 天滚动基线计算 **z-score**
  （分母为个人逐日 log 标准差，用一阶泰勒近似 `SD/基线` 求得）。z>0 表示 HRV 高于平时
  → 副交感主导（恢复）；z<0 → 交感主导（压力）。映射到 50 为平衡、>50 恢复、<50 耗电。
  对应的 `hrvTrend` 文案（"高于平时"/"接近平时"/"低于平时"）帮助用户直观解读。
- **压力分 / 恢复分** 是同一自主神经轴的两面：平衡低于 50 抬升压力、高于 50 抬升恢复，
  心率偏离静息值与睡眠质量作为次要贡献项。
- **充放电模型**：电量 = 晨间充电 − 日内消耗 − 疲劳惩罚 + 即时 HRV 调整。睡眠质量、
  恢复分与平衡轴共同决定晨起点；清醒时长、今日步数 / 活动能量（相对个人基线的超出部分）
  决定日间消耗。
- **个人基线**：取最近 7 天滚动均值（静息心率、HRV、HRV 逐日标准差、睡眠质量、步数、
  活动能量、疲劳负荷），让"高于/低于你平时"的偏离才有意义，而不是对所有人用同一把尺子
  （Firstbeat / HRV4Training 均强调个体化基线）。
- **疲劳负荷**用最近 7 天加权活动量（越近权重越高）累计，连续高强度训练日会压低电量。
- **睡眠为充电主窗口**：按睡眠时长、深睡 / REM 占比、入睡后清醒占比评估睡眠质量
  （Firstbeat 取夜间 HRV 判恢复，本模型用睡眠分期 + HRV 联合判定）。

由于 Apple 健康只提供 SDNN（不提供 RMSSD、逐拍 RR 间期或 LF/HF 频谱），模型在 SDNN 之上
复用上述方法学（对数变换、z-score、充放电积分），而非照搬 Garmin 内部公式。

## 新增指标解读

- **自律（autonomicBalance）**：0–100，50 = 平衡。<50 提示交感占优（身体在消耗），
  >50 提示副交感占优（在恢复）。
- **HRV（带趋势）**：今日 SDNN 毫秒数 + 相对你自己基线的趋势（高于/接近/低于平时）。

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
