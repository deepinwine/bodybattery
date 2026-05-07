import Foundation
import HealthKit

@MainActor
final class HealthDataManager: ObservableObject {
    enum RefreshReason {
        case foreground
        case manualButton
        case phoneRequest
    }

    @Published private(set) var batteryLevel: Int = 100
    @Published private(set) var summary: BodyBatterySummary = .full
    @Published private(set) var canRefreshNow = true
    @Published private(set) var statusText = "未刷新"

    private let healthStore = HKHealthStore()
    private var isForeground = true
    private var isRefreshing = false
    private var didRequestAuthorization = false
    private var resetAnchorsDuringRefresh = false
    private var lastRefreshDate: Date?
    // 真机耗电优化：Watch 端不做后台轮询，且同一前台会话内最短 30 分钟才允许再次读
    // HealthKit。身体电量属于慢变量，过于频繁读取 HR/HRV/睡眠不会显著提升准确性，
    // 反而会增加传感器数据库查询和进程唤醒成本。
    private let minimumRefreshInterval: TimeInterval = 30 * 60
    private let healthQueryTimeout: TimeInterval = 4
    private var heartRateSamples: [Int] = []
    private var restingHeartRateSamples: [Int] = []
    private var hrvSamples: [Int] = []
    private var steps2h = 0
    private var sleepMinutes24h = 0
    private var deepSleepMinutes24h = 0
    private var remSleepMinutes24h = 0
    private var awakeMinutesDuringSleep24h = 0
    private var activeEnergyKilocalories2h = 0
    private var basalEnergyKilocalories2h = 0
    private var awakeMinutesToday = 0
    private var stepsToday = 0
    private var activeEnergyKilocaloriesToday = 0
    private var basalEnergyKilocaloriesToday = 0
    private var latestSleepEndDate: Date?

    private let anchorStore = AnchorStore()

    func requestAuthorization() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        #if targetEnvironment(simulator)
        // Simulator builds use injected aggregates below. Skipping HealthKit authorization avoids
        // simulator-only privacy/HealthKit setup work during launch, which makes Watch UI testing
        // more reliable and keeps the simulated power profile close to the intended foreground-only
        // refresh path.
        return
        #else
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            statusText = "已请求健康权限"
        } catch {
            statusText = "健康权限失败"
        }
        #endif
    }

    func enterForeground() {
        isForeground = true
        updateRefreshAvailability()
    }

    func enterBackground() {
        isForeground = false
        clearTransientState()
        updateRefreshAvailability()
    }

    func refresh(reason: RefreshReason) async {
        guard isForeground else { return }
        guard !isRefreshing else { return }
        guard canRefreshIgnoringReason(reason) else {
            updateRefreshAvailability()
            return
        }
        isRefreshing = true
        resetAnchorsDuringRefresh = false
        defer { isRefreshing = false }

        #if targetEnvironment(simulator)
        injectDebugSamples()
        #else
        await loadAnchoredHealthData(resetAnchorsIfEmpty: true)
        #endif

        guard isForeground else {
            updateRefreshAvailability()
            return
        }

        let latestSummary = BodyBatteryCalculator.summarize(
            BodyBatteryInput(
                restingHeartRate: restingHeartRateSamples.last,
                averageHeartRate2h: average(heartRateSamples),
                hrvSDNNMilliseconds: average(hrvSamples),
                sleepMinutes24h: sleepMinutes24h,
                deepSleepMinutes24h: deepSleepMinutes24h,
                remSleepMinutes24h: remSleepMinutes24h,
                awakeMinutesDuringSleep24h: awakeMinutesDuringSleep24h,
                steps2h: steps2h,
                activeEnergyKilocalories2h: activeEnergyKilocalories2h,
                basalEnergyKilocalories2h: basalEnergyKilocalories2h,
                awakeMinutesToday: awakeMinutesToday,
                stepsToday: stepsToday,
                activeEnergyKilocaloriesToday: activeEnergyKilocaloriesToday,
                basalEnergyKilocaloriesToday: basalEnergyKilocaloriesToday
            )
        )
        summary = latestSummary
        batteryLevel = latestSummary.level
        // 如果本次只是修复旧 anchor，没有真实样本参与计算，不锁 30 分钟冷却；
        // 用户可以立即再点一次刷新读取重置后的样本。
        lastRefreshDate = resetAnchorsDuringRefresh ? nil : Date()
        updateRefreshAvailability()
    }

    private func canRefreshIgnoringReason(_ reason: RefreshReason) -> Bool {
        if reason == .phoneRequest {
            // iPhone 端同步只读取最近快照，不能触发 Watch 后台 HealthKit 查询。
            // 真正刷新只发生在 Watch App 前台打开或 Watch 端手动点击刷新时。
            return false
        }
        guard isForeground else { return false }
        guard let lastRefreshDate else { return true }
        return Date().timeIntervalSince(lastRefreshDate) >= minimumRefreshInterval
    }

    private func updateRefreshAvailability() {
        guard isForeground else {
            canRefreshNow = false
            return
        }
        guard let lastRefreshDate else {
            canRefreshNow = true
            return
        }
        canRefreshNow = Date().timeIntervalSince(lastRefreshDate) >= minimumRefreshInterval
    }

    private func clearTransientState() {
        // We stop all HealthKit work when backgrounded, but keep the already-computed scalar
        // aggregates. HKAnchoredObjectQuery returns only deltas on the next foreground refresh;
        // clearing these values would make the next calculation use only a tiny delta window and
        // appear unsynced with the iPhone. The retained arrays are capped below, so memory stays low.
    }

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private func loadAnchoredHealthData(resetAnchorsIfEmpty: Bool) async {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        let oneDayAgo = now.addingTimeInterval(-24 * 60 * 60)

        async let heartQuery = fetchQuantityValues(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: twoHoursAgo, until: now, anchorSuffix: "2h", limit: 60)
        async let restingQuery = fetchQuantityValues(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: oneDayAgo, until: now, anchorSuffix: "24h", limit: 12)
        async let hrvQuery = fetchQuantityValues(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: oneDayAgo, until: now, anchorSuffix: "24h", limit: 12)
        // 2 小时步数/能量是累计量，用 HKStatisticsQuery 直接读时间窗总和，比遍历样本更省电。
        // HR/HRV/睡眠仍保留 anchored query，以便只处理新增离散样本。
        async let stepsQuery = fetchQuantityTotal(.stepCount, unit: .count(), since: twoHoursAgo, until: now)
        async let activeEnergyQuery = fetchQuantityTotal(.activeEnergyBurned, unit: .kilocalorie(), since: twoHoursAgo, until: now)
        async let basalEnergyQuery = fetchQuantityTotal(.basalEnergyBurned, unit: .kilocalorie(), since: twoHoursAgo, until: now)
        async let sleepQuery = fetchSleepMinutes(since: oneDayAgo, until: now)
        let calendarDayStart = Calendar.current.startOfDay(for: now)
        async let dailyStepsQuery = fetchQuantityTotal(.stepCount, unit: .count(), since: calendarDayStart, until: now)
        async let dailyActiveEnergyQuery = fetchQuantityTotal(.activeEnergyBurned, unit: .kilocalorie(), since: calendarDayStart, until: now)
        async let dailyBasalEnergyQuery = fetchQuantityTotal(.basalEnergyBurned, unit: .kilocalorie(), since: calendarDayStart, until: now)

        let (heart, resting, hrv, steps, activeEnergy, basalEnergy, sleep, dailySteps, dailyActiveEnergy, dailyBasalEnergy) = await (
            heartQuery,
            restingQuery,
            hrvQuery,
            stepsQuery,
            activeEnergyQuery,
            basalEnergyQuery,
            sleepQuery,
            dailyStepsQuery,
            dailyActiveEnergyQuery,
            dailyBasalEnergyQuery
        )
        if let sleepEndDate = sleep.latestEndDate {
            latestSleepEndDate = sleepEndDate
        }
        let drainDayStart = todayDrainStart(now: now, sleepEndDate: latestSleepEndDate)

        append(&heartRateSamples, values: heart.values, limit: 60)
        append(&restingHeartRateSamples, values: resting.values, limit: 12)
        append(&hrvSamples, values: hrv.values, limit: 12)
        steps2h = min(20_000, steps.value)
        activeEnergyKilocalories2h = min(2_000, activeEnergy.value)
        basalEnergyKilocalories2h = min(500, basalEnergy.value)
        if sleep.minutes > 0 { sleepMinutes24h = min(12 * 60, sleepMinutes24h + sleep.minutes) }
        if sleep.deepMinutes > 0 { deepSleepMinutes24h = min(sleepMinutes24h, deepSleepMinutes24h + sleep.deepMinutes) }
        if sleep.remMinutes > 0 { remSleepMinutes24h = min(sleepMinutes24h, remSleepMinutes24h + sleep.remMinutes) }
        if sleep.awakeMinutes > 0 { awakeMinutesDuringSleep24h = min(6 * 60, awakeMinutesDuringSleep24h + sleep.awakeMinutes) }
        awakeMinutesToday = max(0, Int(now.timeIntervalSince(drainDayStart) / 60))
        stepsToday = min(80_000, dailySteps.value)
        activeEnergyKilocaloriesToday = min(5_000, dailyActiveEnergy.value)
        basalEnergyKilocaloriesToday = min(4_000, dailyBasalEnergy.value)

        let hasAnySignal = !heart.values.isEmpty || !resting.values.isEmpty || !hrv.values.isEmpty || steps.value > 0 || activeEnergy.value > 0 || basalEnergy.value > 0 || sleep.minutes > 0 || dailySteps.value > 0 || dailyActiveEnergy.value > 0 || dailyBasalEnergy.value > 0
        if !hasAnySignal, resetAnchorsIfEmpty {
            // If the app previously saved anchors while permissions or samples were unavailable,
            // anchored queries can return empty deltas forever. A one-time foreground reset keeps
            // the normal low-power incremental path while recovering from that stale-anchor state.
            // Do not immediately run a second full query batch here; that doubled launch work on
            // real watches and was a likely cause of the "opening spinner" symptom.
            anchorStore.clearAll(keys: Self.anchorKeys)
            resetAnchorsDuringRefresh = true
            statusText = "未读到样本，已重置下次再试"
            return
        }

        let errors = [heart.errorDescription, resting.errorDescription, hrv.errorDescription, steps.errorDescription, activeEnergy.errorDescription, basalEnergy.errorDescription, sleep.errorDescription, dailySteps.errorDescription, dailyActiveEnergy.errorDescription, dailyBasalEnergy.errorDescription].compactMap { $0 }
        if let firstError = errors.first {
            statusText = "查询失败 \(firstError)"
        } else if hasAnySignal {
            statusText = "HR\(heart.values.count) HRV\(hrv.values.count) 今步\(stepsToday)"
        } else {
            statusText = "未读到近期样本"
        }
    }

    private func append(_ target: inout [Int], values: [Int], limit: Int) {
        guard !values.isEmpty else { return }
        target.append(contentsOf: values)
        if target.count > limit {
            target.removeFirst(target.count - limit)
        }
    }

    private func todayDrainStart(now: Date, sleepEndDate: Date?) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let sleepEndDate, sleepEndDate >= startOfDay, sleepEndDate <= now else {
            return startOfDay
        }
        return sleepEndDate
    }

    private func fetchQuantityValues(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, until end: Date, anchorSuffix: String, limit: Int) async -> QuantityResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return QuantityResult(values: [], errorDescription: "类型缺失") }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let key = "\(identifier.rawValue).\(anchorSuffix)"
        let anchor = anchorStore.anchor(for: key)

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            var query: HKAnchoredObjectQuery?
            query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: limit) { [anchorStore] _, samples, _, newAnchor, error in
                let values = (samples as? [HKQuantitySample] ?? []).map { Int($0.quantity.doubleValue(for: unit).rounded()) }
                let result = QuantityResult(values: values, errorDescription: error.map { Self.shortError($0) })
                if oneShot.resume(returning: result), let newAnchor {
                    anchorStore.save(newAnchor, for: key)
                }
            }
            guard let query else {
                _ = oneShot.resume(returning: QuantityResult(values: [], errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: QuantityResult(values: [], errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func fetchQuantityTotal(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, until end: Date) async -> SumResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return SumResult(value: 0, errorDescription: "类型缺失")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            // 今日步数、活动能量和静息能量是“日累计”显示项。这里使用
            // HKStatisticsQuery 的 cumulativeSum 直接读取系统当天总和，而不是用
            // HKAnchoredObjectQuery 增量累加。这样更接近健康 App 的今日汇总，同时
            // 仍然只在用户刷新/前台刷新时执行，不做后台轮询，查询次数很低。
            var query: HKStatisticsQuery?
            query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                let value = Int((statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0).rounded())
                _ = oneShot.resume(returning: SumResult(value: max(0, value), errorDescription: error.map { Self.shortError($0) }))
            }
            guard let query else {
                _ = oneShot.resume(returning: SumResult(value: 0, errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: SumResult(value: 0, errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func fetchSleepMinutes(since start: Date, until end: Date) async -> SleepResult {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return SleepResult(minutes: 0, errorDescription: "类型缺失") }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let key = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        let anchor = anchorStore.anchor(for: key)

        return await withCheckedContinuation { continuation in
            let oneShot = OneShotContinuation(continuation)
            var query: HKAnchoredObjectQuery?
            query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: 32) { [anchorStore] _, samples, _, newAnchor, error in
                let sleepSamples = samples as? [HKCategorySample] ?? []
                var totalMinutes = 0
                var deepMinutes = 0
                var remMinutes = 0
                var awakeMinutes = 0
                var latestEndDate: Date?

                for sample in sleepSamples {
                    let minutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        totalMinutes += minutes
                        deepMinutes += minutes
                        latestEndDate = Self.maxDate(latestEndDate, sample.endDate)
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        totalMinutes += minutes
                        remMinutes += minutes
                        latestEndDate = Self.maxDate(latestEndDate, sample.endDate)
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        totalMinutes += minutes
                        latestEndDate = Self.maxDate(latestEndDate, sample.endDate)
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakeMinutes += minutes
                    default:
                        break
                    }
                }

                let result = SleepResult(minutes: totalMinutes, deepMinutes: deepMinutes, remMinutes: remMinutes, awakeMinutes: awakeMinutes, latestEndDate: latestEndDate, errorDescription: error.map { Self.shortError($0) })
                if oneShot.resume(returning: result), let newAnchor {
                    anchorStore.save(newAnchor, for: key)
                }
            }
            guard let query else {
                _ = oneShot.resume(returning: SleepResult(minutes: 0, errorDescription: "查询创建失败"))
                return
            }
            scheduleTimeout(for: query, oneShot: oneShot, fallback: SleepResult(minutes: 0, errorDescription: "查询超时"))
            healthStore.execute(query)
        }
    }

    private func scheduleTimeout<Result>(for query: HKQuery, oneShot: OneShotContinuation<Result>, fallback: Result) {
        let timeout = healthQueryTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [healthStore] in
            if oneShot.resume(returning: fallback) {
                healthStore.stop(query)
            }
        }
    }

    nonisolated private static func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }

    nonisolated private static func shortError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    #if targetEnvironment(simulator)
    private func injectDebugSamples() {
        // Debug-only fake aggregates make Simulator UI useful without HealthKit data.
        restingHeartRateSamples = [58]
        heartRateSamples = [72, 76, 80, 82]
        hrvSamples = [51, 54, 55]
        steps2h = 3_200
        sleepMinutes24h = 475
        deepSleepMinutes24h = 85
        remSleepMinutes24h = 90
        awakeMinutesDuringSleep24h = 25
        activeEnergyKilocalories2h = 140
        basalEnergyKilocalories2h = 75
        awakeMinutesToday = 9 * 60 + 30
        stepsToday = 6_800
        activeEnergyKilocaloriesToday = 390
        basalEnergyKilocaloriesToday = 980
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

    private static var anchorKeys: [String] {
        [
            HKQuantityTypeIdentifier.restingHeartRate.rawValue,
            HKQuantityTypeIdentifier.heartRate.rawValue,
            HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
            HKQuantityTypeIdentifier.stepCount.rawValue,
            "\(HKQuantityTypeIdentifier.stepCount.rawValue).2h",
            "\(HKQuantityTypeIdentifier.stepCount.rawValue).today",
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            "\(HKQuantityTypeIdentifier.activeEnergyBurned.rawValue).2h",
            "\(HKQuantityTypeIdentifier.activeEnergyBurned.rawValue).today",
            HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
            "\(HKQuantityTypeIdentifier.basalEnergyBurned.rawValue).2h",
            "\(HKQuantityTypeIdentifier.basalEnergyBurned.rawValue).today",
            "\(HKQuantityTypeIdentifier.heartRate.rawValue).2h",
            "\(HKQuantityTypeIdentifier.restingHeartRate.rawValue).24h",
            "\(HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue).24h",
            HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        ]
    }
}

private struct QuantityResult {
    let values: [Int]
    let errorDescription: String?
}

private struct SumResult {
    let value: Int
    let errorDescription: String?
}

private struct SleepResult {
    let minutes: Int
    let deepMinutes: Int
    let remMinutes: Int
    let awakeMinutes: Int
    let latestEndDate: Date?
    let errorDescription: String?

    init(minutes: Int, deepMinutes: Int = 0, remMinutes: Int = 0, awakeMinutes: Int = 0, latestEndDate: Date? = nil, errorDescription: String?) {
        self.minutes = minutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.awakeMinutes = awakeMinutes
        self.latestEndDate = latestEndDate
        self.errorDescription = errorDescription
    }
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

private final class AnchorStore: @unchecked Sendable {
    private let defaults = UserDefaults.standard

    func anchor(for key: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: "anchor.\(key)") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func save(_ anchor: HKQueryAnchor, for key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: "anchor.\(key)")
    }

    func clearAll(keys: [String]) {
        for key in keys {
            defaults.removeObject(forKey: "anchor.\(key)")
        }
    }
}
