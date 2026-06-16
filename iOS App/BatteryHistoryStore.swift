import Foundation
import SwiftUI

struct BatteryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: Int
    let stressScore: Int
    let recoveryScore: Int
    let drainScore: Int
    let dailyDrainScore: Int
    let fatigueLoadScore: Int
    let sleepQualityScore: Int
    let hrvSDNNMilliseconds: Int?
    let autonomicBalance: Int?
    let hrvTrend: String?
    let steps2h: Int
    let activeEnergyKilocalories2h: Int
    let basalEnergyKilocalories2h: Int
    let awakeMinutesToday: Int
    let stepsToday: Int
    let activeEnergyKilocaloriesToday: Int
    let basalEnergyKilocaloriesToday: Int

    init(
        id: UUID = UUID(),
        date: Date,
        level: Int,
        stressScore: Int = 0,
        recoveryScore: Int = 0,
        drainScore: Int = 0,
        dailyDrainScore: Int = 0,
        fatigueLoadScore: Int = 0,
        sleepQualityScore: Int = 0,
        hrvSDNNMilliseconds: Int? = nil,
        autonomicBalance: Int? = nil,
        hrvTrend: String? = nil,
        steps2h: Int = 0,
        activeEnergyKilocalories2h: Int = 0,
        basalEnergyKilocalories2h: Int = 0,
        awakeMinutesToday: Int = 0,
        stepsToday: Int = 0,
        activeEnergyKilocaloriesToday: Int = 0,
        basalEnergyKilocaloriesToday: Int = 0
    ) {
        self.id = id
        self.date = date
        self.level = min(100, max(0, level))
        self.stressScore = min(100, max(0, stressScore))
        self.recoveryScore = min(100, max(0, recoveryScore))
        self.drainScore = min(100, max(0, drainScore))
        self.dailyDrainScore = min(100, max(0, dailyDrainScore))
        self.fatigueLoadScore = min(100, max(0, fatigueLoadScore))
        self.sleepQualityScore = min(100, max(0, sleepQualityScore))
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.autonomicBalance = autonomicBalance
        self.hrvTrend = hrvTrend
        self.steps2h = max(0, steps2h)
        self.activeEnergyKilocalories2h = max(0, activeEnergyKilocalories2h)
        self.basalEnergyKilocalories2h = max(0, basalEnergyKilocalories2h)
        self.awakeMinutesToday = max(0, awakeMinutesToday)
        self.stepsToday = max(0, stepsToday)
        self.activeEnergyKilocaloriesToday = max(0, activeEnergyKilocaloriesToday)
        self.basalEnergyKilocaloriesToday = max(0, basalEnergyKilocaloriesToday)
    }

    init(date: Date = Date(), summary: BodyBatterySummary) {
        self.init(
            date: date,
            level: summary.level,
            stressScore: summary.stressScore,
            recoveryScore: summary.recoveryScore,
            drainScore: summary.drainScore,
            dailyDrainScore: summary.dailyDrainScore,
            fatigueLoadScore: summary.fatigueLoadScore,
            sleepQualityScore: summary.sleepQualityScore,
            hrvSDNNMilliseconds: summary.hrvSDNNMilliseconds,
            autonomicBalance: summary.autonomicBalance,
            hrvTrend: summary.hrvTrend,
            steps2h: summary.steps2h,
            activeEnergyKilocalories2h: summary.activeEnergyKilocalories2h,
            basalEnergyKilocalories2h: summary.basalEnergyKilocalories2h,
            awakeMinutesToday: summary.awakeMinutesToday,
            stepsToday: summary.stepsToday,
            activeEnergyKilocaloriesToday: summary.activeEnergyKilocaloriesToday,
            basalEnergyKilocaloriesToday: summary.basalEnergyKilocaloriesToday
        )
    }
}

struct DailyBatterySummary: Identifiable, Equatable {
    let id: Date
    let date: Date
    let averageLevel: Int
    let averageStress: Int
    let averageSleepQuality: Int
    let maxSteps: Int
    let maxActiveEnergy: Int
    let latestDailyDrain: Int

    var stepProgress: Double {
        min(1, Double(maxSteps) / 8_000)
    }

    var energyProgress: Double {
        min(1, Double(maxActiveEnergy) / 500)
    }

    var batteryProgress: Double {
        min(1, Double(averageLevel) / 70)
    }
}

@MainActor
final class BatteryHistoryStore: ObservableObject {
    @AppStorage("batteryHistory") private var encodedHistory = ""
    @Published private(set) var records: [BatteryRecord] = []

    var latestLevel: Int? {
        records.sorted { $0.date < $1.date }.last?.level
    }

    var latestSummary: BodyBatterySummary? {
        guard let latest = records.sorted(by: { $0.date < $1.date }).last else { return nil }
        return BodyBatterySummary(
            level: latest.level,
            stressScore: latest.stressScore,
            recoveryScore: latest.recoveryScore,
            drainScore: latest.drainScore,
            dailyDrainScore: latest.dailyDrainScore,
            fatigueLoadScore: latest.fatigueLoadScore,
            sleepQualityScore: latest.sleepQualityScore,
            hrvSDNNMilliseconds: latest.hrvSDNNMilliseconds,
            autonomicBalance: latest.autonomicBalance,
            hrvTrend: latest.hrvTrend,
            steps2h: latest.steps2h,
            activeEnergyKilocalories2h: latest.activeEnergyKilocalories2h,
            basalEnergyKilocalories2h: latest.basalEnergyKilocalories2h,
            awakeMinutesToday: latest.awakeMinutesToday,
            stepsToday: latest.stepsToday,
            activeEnergyKilocaloriesToday: latest.activeEnergyKilocaloriesToday,
            basalEnergyKilocaloriesToday: latest.basalEnergyKilocaloriesToday
        )
    }

    init() {
        load()
    }

    func append(level: Int) {
        records.append(BatteryRecord(date: Date(), level: level))
        trimToStoredRange()
        save()
    }

    func append(summary: BodyBatterySummary) {
        records.append(BatteryRecord(summary: summary))
        trimToStoredRange()
        save()
    }

    func records(lastDays days: Int) -> [BatteryRecord] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 24 * 60 * 60)
        return records
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    func dailySummaries(lastDays days: Int) -> [DailyBatterySummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records(lastDays: days)) { record in
            calendar.startOfDay(for: record.date)
        }
        return grouped.keys.sorted().compactMap { day in
            guard let dayRecords = grouped[day], !dayRecords.isEmpty else { return nil }
            let count = max(dayRecords.count, 1)
            let latest = dayRecords.sorted { $0.date < $1.date }.last
            return DailyBatterySummary(
                id: day,
                date: day,
                averageLevel: dayRecords.map(\.level).reduce(0, +) / count,
                averageStress: dayRecords.map(\.stressScore).reduce(0, +) / count,
                averageSleepQuality: dayRecords.map(\.sleepQualityScore).reduce(0, +) / count,
                maxSteps: dayRecords.map(\.stepsToday).max() ?? 0,
                maxActiveEnergy: dayRecords.map(\.activeEnergyKilocaloriesToday).max() ?? 0,
                latestDailyDrain: latest?.dailyDrainScore ?? 0
            )
        }
    }

    func seedDebugDataIfNeeded() {
        #if targetEnvironment(simulator)
        guard records.isEmpty else { return }
        let calendar = Calendar.current
        let now = Date()
        records = stride(from: 59, through: 0, by: -1).flatMap { dayOffset -> [BatteryRecord] in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let baseLevel = max(32, min(96, 84 - dayOffset / 4 + (dayOffset % 6) * 2))
            let baseStress = max(8, min(72, 18 + (dayOffset % 9) * 5))
            let dayStart = calendar.startOfDay(for: date)
            return [9, 15, 21].map { hour in
                let sampleDate = calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? date
                let hourDrain = hour == 9 ? 0 : (hour == 15 ? 8 : 18)
                let level = max(12, baseLevel - hourDrain)
                let steps = [1_500, 5_200, 8_400][hour == 9 ? 0 : (hour == 15 ? 1 : 2)] + (dayOffset % 5) * 280
                let activeEnergy = [60, 260, 520][hour == 9 ? 0 : (hour == 15 ? 1 : 2)] + (dayOffset % 4) * 25
                let basalEnergy = [220, 820, 1_420][hour == 9 ? 0 : (hour == 15 ? 1 : 2)]
                let hrv = max(28, min(68, 56 - dayOffset % 20))
                return BatteryRecord(
                    date: sampleDate,
                    level: level,
                    stressScore: baseStress + (hour == 21 ? 8 : 0),
                    recoveryScore: max(0, 32 - dayOffset % 12),
                    drainScore: hourDrain,
                    dailyDrainScore: min(100, hourDrain + dayOffset % 18),
                    fatigueLoadScore: min(100, 18 + dayOffset % 44 + (hour == 21 ? 6 : 0)),
                    sleepQualityScore: max(35, min(94, 78 - dayOffset % 16)),
                    hrvSDNNMilliseconds: hrv,
                    autonomicBalance: max(20, min(80, 50 + (hrv - 50) / 2)),
                    hrvTrend: hrv >= 56 ? "高于平时" : (hrv <= 44 ? "低于平时" : "接近平时"),
                    steps2h: hour == 15 ? 2_600 : 900,
                    activeEnergyKilocalories2h: hour == 15 ? 180 : 45,
                    basalEnergyKilocalories2h: 80,
                    awakeMinutesToday: hour * 60,
                    stepsToday: steps,
                    activeEnergyKilocaloriesToday: activeEnergy,
                    basalEnergyKilocaloriesToday: basalEnergy
                )
            }
        }
        save()
        #endif
    }

    private func trimToStoredRange() {
        let cutoff = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        records = Array(records.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }.suffix(1_000))
    }

    private func load() {
        guard let data = encodedHistory.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BatteryRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
        trimToStoredRange()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records),
              let string = String(data: data, encoding: .utf8) else { return }
        encodedHistory = string
    }
}
