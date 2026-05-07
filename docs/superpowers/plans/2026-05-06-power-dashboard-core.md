# 省电型身体电量表实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将当前 BodyBattery 从单一电量值升级为省电核心版，显示身体电量、压力分、恢复分、活动消耗、HRV 趋势，并继续保持 Watch 端前台低频读取。

**架构：** Watch 端只读取并聚合 HealthKit 指标，计算轻量摘要后通过 WatchConnectivity 发送给 iPhone。iPhone 端保存最近 6 小时摘要历史并展示电量/HRV/压力趋势，手动记录类功能留作后续阶段。算法保持常数时间，输入为预聚合标量。

**技术栈：** SwiftUI、HealthKit、WatchConnectivity、XCTest、AppStorage JSON。

---

## 文件结构

- `Shared/BodyBatteryCalculator.swift`：扩展输入模型、输出摘要、压力/恢复/消耗算法和趋势记录类型。
- `BodyBatteryTests/BodyBatteryCalculatorTests.swift`：覆盖 HRV 压力、能量消耗、恢复分和性能测试。
- `Watch App/HealthDataManager.swift`：读取或模拟 HRV、心率、步数、Active Energy、Basal Energy、睡眠，发布摘要。
- `Watch App/BodyBatteryWatchApp.swift`：把摘要变化发送到 iPhone。
- `Watch App/WatchConnectivityManager.swift`：发送/响应轻量摘要字典。
- `Watch App/TodayView.swift`：Watch 端显示电量、压力、HRV、活动消耗摘要。
- `iOS App/iPhoneConnectivityManager.swift`：接收摘要字典。
- `iOS App/BatteryHistoryStore.swift`：保存最近 6 小时摘要记录。
- `iOS App/ContentView.swift`：显示电量、HRV、压力趋势和关键指标。
- `Watch App/Info.plist`：补充新增 HealthKit 读取描述，无需新增网络或后台权限。

## 任务 1：算法模型和测试

**文件：**
- 修改：`Shared/BodyBatteryCalculator.swift`
- 修改：`BodyBatteryTests/BodyBatteryCalculatorTests.swift`

- [ ] **步骤 1：编写失败测试**

新增测试覆盖：
```swift
func testLowHRVAndElevatedHeartRateIncreaseStressScore() {
    let input = BodyBatteryInput(restingHeartRate: 60, averageHeartRate2h: 95, hrvSDNNMilliseconds: 25)
    let summary = BodyBatteryCalculator.summarize(input)
    XCTAssertGreaterThanOrEqual(summary.stressScore, 45)
    XCTAssertLessThan(summary.level, 100)
}

func testActiveAndBasalEnergyIncreaseDrainScore() {
    let input = BodyBatteryInput(activeEnergyKilocalories2h: 450, basalEnergyKilocalories2h: 90, steps2h: 7_500)
    let summary = BodyBatteryCalculator.summarize(input)
    XCTAssertGreaterThanOrEqual(summary.drainScore, 18)
}

func testStrongSleepAndHRVIncreaseRecoveryScore() {
    let input = BodyBatteryInput(restingHeartRate: 58, averageHeartRate2h: 66, hrvSDNNMilliseconds: 58, sleepMinutes24h: 510)
    let summary = BodyBatteryCalculator.summarize(input)
    XCTAssertGreaterThanOrEqual(summary.recoveryScore, 18)
    XCTAssertEqual(summary.level, 100)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：
```bash
xcodebuild test -project BodyBattery.xcodeproj -scheme BodyBattery -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -derivedDataPath DerivedData
```
预期：编译失败或测试失败，原因是 `summarize`、`stressScore`、`drainScore`、`recoveryScore`、能量输入字段尚未存在。

- [ ] **步骤 3：实现最少算法**

新增 `BodyBatterySummary`，保留旧 `calculate(_:)` 调用 `summarize(_).level`。算法只使用整数和小范围 Double：
- 压力：心率偏离 + 低 HRV 扣分。
- 消耗：步数 + active energy + basal energy。
- 恢复：睡眠 + HRV 理想区间。
- 输出字段：`level`、`stressScore`、`recoveryScore`、`drainScore`、`hrvSDNNMilliseconds`、`steps2h`、`activeEnergyKilocalories2h`、`basalEnergyKilocalories2h`。

- [ ] **步骤 4：运行测试验证通过**

运行同上测试命令。预期：所有算法测试通过，性能测试仍低于 5ms。

## 任务 2：Watch 端健康数据摘要

**文件：**
- 修改：`Watch App/HealthDataManager.swift`
- 修改：`Watch App/BodyBatteryWatchApp.swift`

- [ ] **步骤 1：添加摘要状态**

`HealthDataManager` 增加 `@Published private(set) var summary = BodyBatterySummary.full`，刷新后写入 summary，并让 `batteryLevel` 保持从 summary 派生。

- [ ] **步骤 2：读取能量类型**

在 read types 中增加：
```swift
HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
```
只在前台 refresh 中读取最近 2 小时 active energy 和 basal energy，不新增后台 observer，不新增 Timer。

- [ ] **步骤 3：Debug 假数据**

模拟器/DEBUG 下设置：
```swift
activeEnergyKilocalories2h = 160
basalEnergyKilocalories2h = 85
hrvSamples = [48, 52, 55]
```

- [ ] **步骤 4：构建 Watch target**

运行：
```bash
xcodebuild clean build -project BodyBattery.xcodeproj -scheme BodyBatteryWatchApp -destination 'generic/platform=watchOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```
预期：BUILD SUCCEEDED。

## 任务 3：WatchConnectivity 摘要传输

**文件：**
- 修改：`Watch App/WatchConnectivityManager.swift`
- 修改：`iOS App/iPhoneConnectivityManager.swift`

- [ ] **步骤 1：定义摘要字典**

发送字段：
```swift
[
  "batteryLevel": Int,
  "stressScore": Int,
  "recoveryScore": Int,
  "drainScore": Int,
  "hrv": Int,
  "steps": Int,
  "activeEnergy": Int,
  "basalEnergy": Int
]
```

- [ ] **步骤 2：Watch 端只在关键值变化时发送**

变化阈值：电量、压力、HRV 任一变化大于 1 才发送；不可达时只缓存最新摘要，不维护重试队列。

- [ ] **步骤 3：iOS 端接收摘要**

`iPhoneConnectivityManager` 增加 `@Published private(set) var summary: BodyBatterySummary?`，保留 `batteryLevel` 兼容旧 UI。

- [ ] **步骤 4：构建验证**

运行 Watch 和 iOS 通用构建命令，预期均成功。

## 任务 4：iPhone 趋势和面板

**文件：**
- 修改：`iOS App/BatteryHistoryStore.swift`
- 修改：`iOS App/ContentView.swift`

- [ ] **步骤 1：历史记录改为摘要**

`BatteryRecord` 增加压力、恢复、消耗、HRV、步数、能量字段。AppStorage 仍保存最近 6 小时 JSON，Debug 下预置电量/HRV/压力趋势。

- [ ] **步骤 2：新增多趋势折线**

复用轻量 `Path` 绘制电量、HRV、压力三条趋势。避免第三方图表库，避免动画。

- [ ] **步骤 3：新增关键指标网格**

显示：压力、恢复、消耗、HRV、步数、活动能量、静息能量。保持 OLED 深色背景。

- [ ] **步骤 4：iOS 构建**

运行：
```bash
xcodebuild build -project BodyBattery.xcodeproj -scheme BodyBattery -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```
预期：BUILD SUCCEEDED。

## 任务 5：Watch 端省电 UI

**文件：**
- 修改：`Watch App/TodayView.swift`

- [ ] **步骤 1：添加摘要文本**

圆环下方显示压力、HRV、消耗三行小文本；`isLuminanceReduced` 下仍只显示数字电量。

- [ ] **步骤 2：保持无动画轻量绘制**

不添加渐变、不添加 Timer、不添加复杂图表。HRV 趋势只在 Watch 端以箭头或文本显示。

- [ ] **步骤 3：Watch 构建并启动**

运行：
```bash
xcodebuild clean build -project BodyBattery.xcodeproj -scheme BodyBatteryWatchApp -destination 'generic/platform=watchOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
xcrun simctl install BEDD9198-A4A1-47EC-B790-B80A83F5F861 DerivedData/Build/Products/Debug-watchsimulator/BodyBatteryWatchApp.app
xcrun simctl launch BEDD9198-A4A1-47EC-B790-B80A83F5F861 com.example.BodyBattery.watchkitapp
```
预期：构建成功，launch 返回进程号。

## 自检

- 规格覆盖：HRV、压力、活动消耗、静息代谢、运动代谢、HRV 趋势已覆盖。日晒、呼吸频次、环境音量、情绪、喝水、咖啡明确留到后续阶段，符合用户选择的 A 省电型。
- 占位符扫描：没有待定步骤；每个任务都有明确文件和验证命令。
- 类型一致性：核心类型统一为 `BodyBatteryInput`、`BodyBatterySummary`、`BatteryRecord`。
