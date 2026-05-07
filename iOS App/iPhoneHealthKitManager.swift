import Foundation
import HealthKit
import UserNotifications

@MainActor
final class iPhoneHealthKitManager: ObservableObject {
    @Published private(set) var healthStatusText = "未连接 Apple 健康"
    @Published private(set) var notificationStatusText = "未开启通知"
    @Published private(set) var summary: BodyBatterySummary?
    @Published private(set) var isRefreshing = false

    private let healthStore = HKHealthStore()
    private let healthQueryTimeout: TimeInterval = 5
    private let minimumRefreshInterval: TimeInterval = 20 * 60
    private var lastRefreshDate: Date?
    private var cachedBaselineDay: Date?
    private var cachedBaseline: BodyBatteryBaseline?

    /// 用户主动授权时才弹系统权限页；日常刷新只读已有权限范围，不反复弹窗。
    func requestHealthAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthStatusText = "当前设备不支持健康数据"
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            healthStatusText = "已连接 Apple 健康"
        } catch {
            healthStatusText = "健康权限未完成"
        }
    }

    func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            notificationStatusText = granted ? "通知已开启" : "通知未开启"
        } catch {
            notificationStatusText = "通知权限失败"
        }
    }

    /// iPhone 端身体电量刷新入口。
    ///
    /// 省电策略：
    /// - 不使用 Timer，不注册 HKObserverQuery，不做后台轮询。
    /// - 只有 App 打开后的防抖刷新或用户点击“刷新健康数据”才执行。
    /// - 步数、活动能量、静息能量使用 HKStatisticsQuery 取系统已聚合总和，避免遍历大量样本。
    /// - 心率、HRV、睡眠只读取很小时间窗的聚合值，计算阶段只处理标量。
    @discardableResult
    func refreshSummary(force: Bool) async -> BodyBatterySummary? {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthStatusText = "当前设备不支持健康数据"
            return summary
        }
        guard !isRefreshing else { return summary }
        if !force, let lastRefreshDate, Date().timeIntervalSince(lastRefreshDate) < minimumRefreshInterval {
            healthStatusText = "已显示最近健康快照"
            return nil
        }

        isRefreshing = true
        healthStatusText = "正在读取 Apple 健康..."
        defer { isRefreshing = false }

        #if targetEnvironment(simulator)
        let debugSummary = debugSummary()
        summary = debugSummary
        lastRefreshDate = Date()
        healthStatusText = "模拟健康数据已刷新"
        return debugSummary
        #else
        let now = Date()
        let calendar = Calendar.current
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        let oneDayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let todayStart = calendar.startOfDay(for: now)

        async let heartRate = fetchAverageQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: twoHoursAgo, until: now, limit: 80)
        async let restingHeartRate = fetchLatestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: oneDayAgo, until: now)
        async let hrv = fetchAverageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: oneDayAgo, until: now, limit: 24)
        async let sleep = fetchSleepMinutes(since: oneDayAgo, until: now, limit: 48)
        async let steps2h = fetchQuantityTotal(.stepCount, unit: .count(), since: twoHoursAgo, until: now)
        async let activeEnergy2h = fetchQuantityTotal(.activeEnergyBurned, unit: .kilocalorie(), since: twoHoursAgo, until: now)
        async let basalEnergy2h = fetchQuantityTotal(.basalEnergyBurned, unit: .kilocalorie(), since: twoHoursAgo, until: now)
        async let stepsToday = fetchQuantityTotal(.stepCount, unit: .count(), since: todayStart, until: now)
        async let activeEnergyToday = fetchQuantityTotal(.activeEnergyBurned, unit: .kilocalorie(), since: todayStart, until: now)
        async let basalEnergyToday = fetchQuantityTotal(.basalEnergyBurned, unit: .kilocalorie(), since: todayStart, until: now)
        async let baseline = fetchPersonalBaseline(until: todayStart)

        let currentSleep = await sleep
        let currentHeartRate = await heartRate
        let currentRestingHeartRate = await restingHeartRate
        let currentHRV = await hrv
        let currentSteps2h = await steps2h
        let currentActiveEnergy2h = await activeEnergy2h
        let currentBasalEnergy2h = await basalEnergy2h
        let currentStepsToday = await stepsToday
        let currentActiveEnergyToday = await activeEnergyToday
        let currentBasalEnergyToday = await basalEnergyToday
        let currentBaseline = await baseline
        let currentInput = BodyBatteryInput(
            restingHeartRate: currentRestingHeartRate.value,
            averageHeartRate2h: currentHeartRate.value,
            hrvSDNNMilliseconds: currentHRV.value,
            sleepMinutes24h: currentSleep.minutes,
            deepSleepMinutes24h: currentSleep.deepMinutes,
            remSleepMinutes24h: currentSleep.remMinutes,
            awakeMinutesDuringSleep24h: currentSleep.awakeMinutes,
            steps2h: currentSteps2h.value ?? 0,
            activeEnergyKilocalories2h: currentActiveEnergy2h.value ?? 0,
            basalEnergyKilocalories2h: currentBasalEnergy2h.value ?? 0,
            awakeMinutesToday: max(0, Int(now.timeIntervalSince(todayStart) / 60)),
            stepsToday: currentStepsToday.value ?? 0,
            activeEnergyKilocaloriesToday: currentActiveEnergyToday.value ?? 0,
            basalEnergyKilocaloriesToday: currentBasalEnergyToday.value ?? 0
        )

        let latestSummary = BodyBatteryCalculator.summarize(currentInput, baseline: currentBaseline)
        summary = latestSummary
        lastRefreshDate = now
        healthStatusText = "Apple 健康已刷新"
        return latestSummary
        #endif
    }

    private func fetchPersonalBaseline(until todayStart: Date) async -> BodyBatteryBaseline? {
        if cachedBaselineDay == todayStart {
            return cachedBaseline
        }

        let start = todayStart.addingTimeInterval(-7 * 24 * 60 * 60)

        async let resting = fetchAverageQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: start, until: todayStart, limit: 32)
        async let hrv = fetchAverageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: start, until: todayStart, limit: 80)
        async let steps = fetchQuantityTotal(.stepCount, unit: .count(), since: start, until: todayStart)
        async let activeEnergy = fetchQuantityTotal(.activeEnergyBurned, unit: .kilocalorie(), since: start, until: todayStart)
        async let sleep = fetchSleepMinutes(since: start, until: todayStart, limit: 160)

        let baselineSleep = await sleep
        let sleepDays = max(1, baselineSleep.daysWithSleep)
        let sleepInput = BodyBatteryInput(
            sleepMinutes24h: baselineSleep.minutes / sleepDays,
            deepSleepMinutes24h: baselineSleep.deepMinutes / sleepDays,
            remSleepMinutes24h: baselineSleep.remMinutes / sleepDays,
            awakeMinutesDuringSleep24h: baselineSleep.awakeMinutes / sleepDays
        )
        let sleepQuality = baselineSleep.minutes > 0 ? BodyBatteryCalculator.summarize(sleepInput).sleepQualityScore : nil

        let baselineResting = await resting
        let baselineHRV = await hrv
        let baselineSteps = await steps
        let baselineActiveEnergy = await activeEnergy

        let baseline = BodyBatteryBaseline(
            restingHeartRate: baselineResting.value,
            hrvSDNNMilliseconds: baselineHRV.value,
            sleepQualityScore: sleepQuality,
            sleepMinutes: baselineSleep.minutes > 0 ? baselineSleep.minutes / sleepDays : nil,
            stepsToday: (baselineSteps.value ?? 0) / 7,
            activeEnergyKilocaloriesToday: (baselineActiveEnergy.value ?? 0) / 7
        )
        cachedBaselineDay = todayStart
        cachedBaseline = baseline
        return baseline
    }

    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, until end: Date) async -> HealthQuantityResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return HealthQuantityResult(value: nil, errorDescription: "类型缺失")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            var query: HKSampleQuery?
            query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                let value = (samples?.first as? HKQuantitySample).map { Int($0.quantity.doubleValue(for: unit).rounded()) }
                _ = oneShot.resume(returning: HealthQuantityResult(value: value, errorDescription: error.map { Self.shortError($0) }))
            }
            guard let query else {
                _ = oneShot.resume(returning: HealthQuantityResult(value: nil, errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: HealthQuantityResult(value: nil, errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func fetchAverageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, until end: Date, limit: Int) async -> HealthQuantityResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return HealthQuantityResult(value: nil, errorDescription: "类型缺失")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            var query: HKSampleQuery?
            query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: nil) { _, samples, error in
                let values = (samples as? [HKQuantitySample] ?? []).map { Int($0.quantity.doubleValue(for: unit).rounded()) }
                let average = values.isEmpty ? nil : values.reduce(0, +) / values.count
                _ = oneShot.resume(returning: HealthQuantityResult(value: average, errorDescription: error.map { Self.shortError($0) }))
            }
            guard let query else {
                _ = oneShot.resume(returning: HealthQuantityResult(value: nil, errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: HealthQuantityResult(value: nil, errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func fetchQuantityTotal(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, until end: Date) async -> HealthQuantityResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return HealthQuantityResult(value: 0, errorDescription: "类型缺失")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            var query: HKStatisticsQuery?
            query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                let total = Int((statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0).rounded())
                _ = oneShot.resume(returning: HealthQuantityResult(value: max(0, total), errorDescription: error.map { Self.shortError($0) }))
            }
            guard let query else {
                _ = oneShot.resume(returning: HealthQuantityResult(value: 0, errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: HealthQuantityResult(value: 0, errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func fetchSleepMinutes(since start: Date, until end: Date, limit: Int) async -> HealthSleepResult {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return HealthSleepResult(errorDescription: "类型缺失")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            var query: HKSampleQuery?
            query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: nil) { _, samples, error in
                var result = HealthSleepResult(errorDescription: error.map { Self.shortError($0) })
                let calendar = Calendar.current
                var sleepDays = Set<Date>()

                for sample in samples as? [HKCategorySample] ?? [] {
                    let minutes = max(0, Int(sample.endDate.timeIntervalSince(sample.startDate) / 60))
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        result.minutes += minutes
                        result.deepMinutes += minutes
                        sleepDays.insert(calendar.startOfDay(for: sample.endDate))
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        result.minutes += minutes
                        result.remMinutes += minutes
                        sleepDays.insert(calendar.startOfDay(for: sample.endDate))
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        result.minutes += minutes
                        sleepDays.insert(calendar.startOfDay(for: sample.endDate))
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        result.awakeMinutes += minutes
                    default:
                        break
                    }
                }
                result.daysWithSleep = sleepDays.count
                _ = oneShot.resume(returning: result)
            }
            guard let query else {
                _ = oneShot.resume(returning: HealthSleepResult(errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: HealthSleepResult(errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func scheduleTimeout<Result>(for query: HKQuery, oneShot: OneShotContinuation<Result>, fallback: Result) {
        DispatchQueue.main.asyncAfter(deadline: .now() + healthQueryTimeout) { [healthStore] in
            if oneShot.resume(returning: fallback) {
                healthStore.stop(query)
            }
        }
    }

    nonisolated private static func shortError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    #if targetEnvironment(simulator)
    private func debugSummary() -> BodyBatterySummary {
        let input = BodyBatteryInput(
            restingHeartRate: 58,
            averageHeartRate2h: 76,
            hrvSDNNMilliseconds: 52,
            sleepMinutes24h: 455,
            deepSleepMinutes24h: 78,
            remSleepMinutes24h: 92,
            awakeMinutesDuringSleep24h: 28,
            steps2h: 2_200,
            activeEnergyKilocalories2h: 110,
            basalEnergyKilocalories2h: 70,
            awakeMinutesToday: 620,
            stepsToday: 6_900,
            activeEnergyKilocaloriesToday: 430,
            basalEnergyKilocaloriesToday: 1_050
        )
        let baseline = BodyBatteryBaseline(
            restingHeartRate: 61,
            hrvSDNNMilliseconds: 46,
            sleepQualityScore: 70,
            sleepMinutes: 430,
            stepsToday: 7_200,
            activeEnergyKilocaloriesToday: 390
        )
        return BodyBatteryCalculator.summarize(input, baseline: baseline)
    }
    #endif

    private static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ].compactMap { $0 }.reduce(into: Set<HKObjectType>()) { $0.insert($1) }
    }
}

private struct HealthQuantityResult {
    var value: Int?
    var errorDescription: String?
}

private struct HealthSleepResult {
    var minutes = 0
    var deepMinutes = 0
    var remMinutes = 0
    var awakeMinutes = 0
    var daysWithSleep = 0
    var errorDescription: String?
}

private final class OneShotContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }
}
