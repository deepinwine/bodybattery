# iOS Onboarding Health Goals 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 iPhone App 添加首次启动 onboarding，收集用户画像、请求通知/健康权限，并生成可编辑健康目标。

**架构：** iOS 端新增本地 `OnboardingStore` 保存完成状态、生日、选项和目标；新增 `iPhoneHealthKitManager` 只在用户点击授权时请求 HealthKit 权限；新增 `OnboardingView` 作为 `ContentView` 前的全屏入口。现有 Tab 主界面不重写，只在完成 onboarding 后展示。

**技术栈：** SwiftUI、AppStorage、HealthKit、UserNotifications。

---

### 任务 1：本地画像与目标模型

**文件：**
- 创建：`iOS App/OnboardingStore.swift`
- 修改：`BodyBattery.xcodeproj/project.pbxproj`

- [x] **步骤 1：定义画像、目标、心率区间模型**
- [x] **步骤 2：用 JSON + AppStorage 持久化目标和选择**

### 任务 2：权限管理

**文件：**
- 创建：`iOS App/iPhoneHealthKitManager.swift`
- 修改：`iOS App/Info.plist`
- 修改：`iOS App/BodyBatteryiOS.entitlements`
- 修改：`BodyBattery.xcodeproj/project.pbxproj`

- [x] **步骤 1：实现 HealthKit requestAuthorization**
- [x] **步骤 2：实现通知权限请求**
- [x] **步骤 3：添加 iOS HealthKit entitlement 与隐私描述**

### 任务 3：全屏 Onboarding UI

**文件：**
- 创建：`iOS App/OnboardingView.swift`
- 修改：`iOS App/BodyBatteryiOSApp.swift`
- 修改：`iOS App/ContentView.swift`
- 修改：`BodyBattery.xcodeproj/project.pbxproj`

- [x] **步骤 1：在 App 注入 onboarding/health manager**
- [x] **步骤 2：ContentView 未完成时显示 onboarding**
- [x] **步骤 3：实现全部用户流程和分析进度**
- [x] **步骤 4：实现目标卡片编辑 sheet**

### 任务 4：验证

**文件：**
- 修改：无

- [x] **步骤 1：构建 iOS target**
- [x] **步骤 2：运行现有测试**
