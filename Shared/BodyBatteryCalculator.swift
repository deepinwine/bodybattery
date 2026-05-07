import Foundation
import SwiftUI

/// Compact value object passed from HealthKit collection code into the local battery algorithm.
///
/// The fields are already aggregated by `HealthDataManager`, so calculation never iterates over raw
/// samples. This keeps the CPU cost predictable and tiny on Apple Watch.
public struct BodyBatteryInput: Equatable, Sendable {
    public var restingHeartRate: Int?
    public var averageHeartRate2h: Int?
    public var hrvSDNNMilliseconds: Int?
    public var sleepMinutes24h: Int
    public var deepSleepMinutes24h: Int
    public var remSleepMinutes24h: Int
    public var awakeMinutesDuringSleep24h: Int
    public var steps2h: Int
    public var activeEnergyKilocalories2h: Int
    public var basalEnergyKilocalories2h: Int
    public var awakeMinutesToday: Int
    public var stepsToday: Int
    public var activeEnergyKilocaloriesToday: Int
    public var basalEnergyKilocaloriesToday: Int

    public init(
        restingHeartRate: Int? = nil,
        averageHeartRate2h: Int? = nil,
        hrvSDNNMilliseconds: Int? = nil,
        sleepMinutes24h: Int = 0,
        deepSleepMinutes24h: Int = 0,
        remSleepMinutes24h: Int = 0,
        awakeMinutesDuringSleep24h: Int = 0,
        steps2h: Int = 0,
        activeEnergyKilocalories2h: Int = 0,
        basalEnergyKilocalories2h: Int = 0,
        awakeMinutesToday: Int = 0,
        stepsToday: Int = 0,
        activeEnergyKilocaloriesToday: Int = 0,
        basalEnergyKilocaloriesToday: Int = 0
    ) {
        self.restingHeartRate = restingHeartRate
        self.averageHeartRate2h = averageHeartRate2h
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.sleepMinutes24h = sleepMinutes24h
        self.deepSleepMinutes24h = deepSleepMinutes24h
        self.remSleepMinutes24h = remSleepMinutes24h
        self.awakeMinutesDuringSleep24h = awakeMinutesDuringSleep24h
        self.steps2h = steps2h
        self.activeEnergyKilocalories2h = activeEnergyKilocalories2h
        self.basalEnergyKilocalories2h = basalEnergyKilocalories2h
        self.awakeMinutesToday = awakeMinutesToday
        self.stepsToday = stepsToday
        self.activeEnergyKilocaloriesToday = activeEnergyKilocaloriesToday
        self.basalEnergyKilocaloriesToday = basalEnergyKilocaloriesToday
    }
}

/// Small summary transmitted between Watch and iPhone.
///
/// The summary is intentionally scalar-only so WatchConnectivity payloads stay tiny and the iPhone
/// can build trends without rereading HealthKit. No raw HealthKit samples cross the device boundary.
public struct BodyBatterySummary: Codable, Equatable, Sendable {
    public var level: Int
    public var stressScore: Int
    public var recoveryScore: Int
    public var drainScore: Int
    public var dailyDrainScore: Int
    public var fatigueLoadScore: Int
    public var sleepQualityScore: Int
    public var hrvSDNNMilliseconds: Int?
    public var steps2h: Int
    public var activeEnergyKilocalories2h: Int
    public var basalEnergyKilocalories2h: Int
    public var awakeMinutesToday: Int
    public var stepsToday: Int
    public var activeEnergyKilocaloriesToday: Int
    public var basalEnergyKilocaloriesToday: Int

    public init(
        level: Int,
        stressScore: Int,
        recoveryScore: Int,
        drainScore: Int,
        dailyDrainScore: Int = 0,
        fatigueLoadScore: Int = 0,
        sleepQualityScore: Int = 0,
        hrvSDNNMilliseconds: Int? = nil,
        steps2h: Int = 0,
        activeEnergyKilocalories2h: Int = 0,
        basalEnergyKilocalories2h: Int = 0,
        awakeMinutesToday: Int = 0,
        stepsToday: Int = 0,
        activeEnergyKilocaloriesToday: Int = 0,
        basalEnergyKilocaloriesToday: Int = 0
    ) {
        self.level = Self.clamp(level)
        self.stressScore = Self.clamp(stressScore)
        self.recoveryScore = Self.clamp(recoveryScore)
        self.drainScore = Self.clamp(drainScore)
        self.dailyDrainScore = Self.clamp(dailyDrainScore)
        self.fatigueLoadScore = Self.clamp(fatigueLoadScore)
        self.sleepQualityScore = Self.clamp(sleepQualityScore)
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.steps2h = max(0, steps2h)
        self.activeEnergyKilocalories2h = max(0, activeEnergyKilocalories2h)
        self.basalEnergyKilocalories2h = max(0, basalEnergyKilocalories2h)
        self.awakeMinutesToday = max(0, awakeMinutesToday)
        self.stepsToday = max(0, stepsToday)
        self.activeEnergyKilocaloriesToday = max(0, activeEnergyKilocaloriesToday)
        self.basalEnergyKilocaloriesToday = max(0, basalEnergyKilocaloriesToday)
    }

    public static let full = BodyBatterySummary(level: 100, stressScore: 0, recoveryScore: 0, drainScore: 0)

    private static func clamp(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

/// Personal rolling baseline learned from recent Apple Health history.
///
/// Garmin publicly describes Body Battery as depending on HRV, stress, activity, sleep, and a
/// several-day learning period. This struct represents the local equivalent of that learning
/// period without storing raw samples: iPhone HealthKit code reduces recent days into six scalar
/// baselines, then the pure calculator compares today's signals against "your normal" instead of
/// treating every person the same.
public struct BodyBatteryBaseline: Codable, Equatable, Sendable {
    public var restingHeartRate: Int?
    public var hrvSDNNMilliseconds: Int?
    public var sleepQualityScore: Int?
    public var sleepMinutes: Int?
    public var stepsToday: Int?
    public var activeEnergyKilocaloriesToday: Int?
    public var fatigueLoadScore: Int?

    public init(
        restingHeartRate: Int? = nil,
        hrvSDNNMilliseconds: Int? = nil,
        sleepQualityScore: Int? = nil,
        sleepMinutes: Int? = nil,
        stepsToday: Int? = nil,
        activeEnergyKilocaloriesToday: Int? = nil,
        fatigueLoadScore: Int? = nil
    ) {
        self.restingHeartRate = restingHeartRate
        self.hrvSDNNMilliseconds = hrvSDNNMilliseconds
        self.sleepQualityScore = sleepQualityScore
        self.sleepMinutes = sleepMinutes
        self.stepsToday = stepsToday
        self.activeEnergyKilocaloriesToday = activeEnergyKilocaloriesToday
        self.fatigueLoadScore = fatigueLoadScore.map { min(100, max(0, $0)) }
    }
}

/// Deterministic, low-cost body battery algorithm.
///
/// Power strategy:
/// - Inputs are pre-aggregated scalar values; the function does not allocate large collections.
/// - Most work uses integer arithmetic. HRV band checks are simple comparisons.
/// - The full path is constant-time, which is suitable for running after a foreground refresh.
public enum BodyBatteryCalculator {
    public static func calculate(_ input: BodyBatteryInput) -> Int {
        summarize(input, baseline: nil).level
    }

    public static func calculate(_ input: BodyBatteryInput, baseline: BodyBatteryBaseline?) -> Int {
        summarize(input, baseline: baseline).level
    }

    /// Returns the full low-power summary used by Watch and iPhone.
    ///
    /// Power strategy:
    /// - Constant-time arithmetic over scalar aggregates.
    /// - No loops except tiny fixed-band checks and no allocations beyond the returned value.
    /// - HealthKit sample iteration remains in the data manager, outside this pure function.
    public static func summarize(_ input: BodyBatteryInput, baseline: BodyBatteryBaseline? = nil) -> BodyBatterySummary {
        let sleepQualityScore = sleepQualityScore(for: input)
        let stressScore = stressScore(for: input, sleepQualityScore: sleepQualityScore, baseline: baseline)
        let recoveryScore = recoveryScore(for: input, sleepQualityScore: sleepQualityScore, baseline: baseline)
        let drainScore = drainScore(for: input)
        let dailyDrainScore = dailyDrainScore(for: input, baseline: baseline)
        let fatigueLoadScore = baseline?.fatigueLoadScore ?? 0
        let fatiguePenalty = fatigueLoadScore / 3
        let baselineLevel = baselineLevel(for: input, recoveryScore: recoveryScore, sleepQualityScore: sleepQualityScore, baseline: baseline)
        let shortRecoveryBuffer = input.sleepMinutes24h > 0 ? min(10, recoveryScore / 3) : recoveryScore
        let level = min(100, max(0, baselineLevel + shortRecoveryBuffer - stressScore - drainScore - dailyDrainScore - fatiguePenalty))

        return BodyBatterySummary(
            level: level,
            stressScore: stressScore,
            recoveryScore: recoveryScore,
            drainScore: drainScore,
            dailyDrainScore: dailyDrainScore,
            fatigueLoadScore: fatigueLoadScore,
            sleepQualityScore: sleepQualityScore,
            hrvSDNNMilliseconds: input.hrvSDNNMilliseconds,
            steps2h: input.steps2h,
            activeEnergyKilocalories2h: input.activeEnergyKilocalories2h,
            basalEnergyKilocalories2h: input.basalEnergyKilocalories2h,
            awakeMinutesToday: input.awakeMinutesToday,
            stepsToday: input.stepsToday,
            activeEnergyKilocaloriesToday: input.activeEnergyKilocaloriesToday,
            basalEnergyKilocaloriesToday: input.basalEnergyKilocaloriesToday
        )
    }

    /// Estimates the "morning charge" after sleep, then the model drains it through the day.
    ///
    /// With sleep data, recovery and sleep quality set the day's starting point. Without sleep data
    /// we keep the legacy 100 baseline so first-run devices do not show an artificially low value.
    private static func baselineLevel(for input: BodyBatteryInput, recoveryScore: Int, sleepQualityScore: Int, baseline: BodyBatteryBaseline?) -> Int {
        guard input.sleepMinutes24h > 0 else { return 100 }
        let sufficientSleepBuffer = sleepQualityScore >= 55 ? 6 : 0
        var level = 55 + recoveryScore + sleepQualityScore / 3 + sufficientSleepBuffer

        if let baseline {
            if let usualSleep = baseline.sleepMinutes, usualSleep > 0 {
                let sleepDelta = input.sleepMinutes24h - usualSleep
                if sleepDelta >= 45 {
                    level += 4
                } else if sleepDelta <= -90 {
                    level -= 10
                } else if sleepDelta <= -45 {
                    level -= 5
                }
            }
            if let usualSleepQuality = baseline.sleepQualityScore {
                let qualityDelta = sleepQualityScore - usualSleepQuality
                if qualityDelta >= 12 {
                    level += 5
                } else if qualityDelta <= -20 {
                    level -= 12
                } else if qualityDelta <= -10 {
                    level -= 6
                }
            }
        }

        return min(100, max(35, level))
    }

    private static func stressScore(for input: BodyBatteryInput, sleepQualityScore: Int, baseline: BodyBatteryBaseline?) -> Int {
        var score = 0

        if let resting = input.restingHeartRate, let average = input.averageHeartRate2h {
            let delta = max(0, average - resting)
            score += (delta / 10) * 10
        }

        if let hrv = input.hrvSDNNMilliseconds {
            switch hrv {
            case ..<30:
                score += 20
            case 30..<40:
                score += 12
            case 66...:
                score += 6
            default:
                break
            }
        }

        if input.sleepMinutes24h > 0 {
            switch sleepQualityScore {
            case ..<35:
                score += 24
            case 35..<55:
                score += 16
            case 55..<70:
                score += 6
            default:
                break
            }
        }

        if let baseline {
            if let usualHRV = baseline.hrvSDNNMilliseconds, let hrv = input.hrvSDNNMilliseconds, usualHRV > 0 {
                let hrvDropPercent = max(0, (usualHRV - hrv) * 100 / usualHRV)
                if hrvDropPercent >= 30 {
                    score += 18
                } else if hrvDropPercent >= 20 {
                    score += 12
                } else if hrvDropPercent >= 10 {
                    score += 6
                }
            }
            if let usualResting = baseline.restingHeartRate, let resting = input.restingHeartRate {
                let restingDelta = resting - usualResting
                if restingDelta >= 12 {
                    score += 16
                } else if restingDelta >= 8 {
                    score += 10
                } else if restingDelta >= 5 {
                    score += 5
                }
            }
            if let usualSleepQuality = baseline.sleepQualityScore, input.sleepMinutes24h > 0 {
                let qualityDrop = usualSleepQuality - sleepQualityScore
                if qualityDrop >= 25 {
                    score += 12
                } else if qualityDrop >= 15 {
                    score += 7
                }
            }
        }

        return min(100, max(0, score))
    }

    private static func recoveryScore(for input: BodyBatteryInput, sleepQualityScore: Int, baseline: BodyBatteryBaseline?) -> Int {
        var score = 0

        switch input.sleepMinutes24h {
        case 1..<240:
            score -= 12
        case 240..<330:
            score += 2
        case 330..<(7 * 60):
            score += 7
        case (7 * 60)..<(9 * 60):
            score += 14
        case (9 * 60)...:
            score += 12
        default:
            break
        }

        if input.sleepMinutes24h > 0 {
            switch sleepQualityScore {
            case ..<35:
                score -= 12
            case 35..<55:
                score -= 6
            case 55..<70:
                score += 2
            case 70..<85:
                score += 8
            default:
                score += 12
            }
        }

        if let hrv = input.hrvSDNNMilliseconds {
            switch hrv {
            case 30..<40:
                score += 4
            case 40..<50:
                score += 8
            case 50...65:
                score += 12
            default:
                break
            }
        }

        if let resting = input.restingHeartRate, let average = input.averageHeartRate2h, average <= resting + 10 {
            score += 4
        }

        if let baseline {
            if let usualHRV = baseline.hrvSDNNMilliseconds, let hrv = input.hrvSDNNMilliseconds, usualHRV > 0 {
                let hrvRisePercent = max(0, (hrv - usualHRV) * 100 / usualHRV)
                if hrvRisePercent >= 25 {
                    score += 10
                } else if hrvRisePercent >= 15 {
                    score += 7
                } else if hrvRisePercent >= 8 {
                    score += 4
                }
            }
            if let usualResting = baseline.restingHeartRate, let resting = input.restingHeartRate {
                let restingImprovement = usualResting - resting
                if restingImprovement >= 8 {
                    score += 6
                } else if restingImprovement >= 4 {
                    score += 3
                }
            }
            if let usualSleepQuality = baseline.sleepQualityScore {
                let qualityRise = sleepQualityScore - usualSleepQuality
                if qualityRise >= 15 {
                    score += 8
                } else if qualityRise >= 8 {
                    score += 4
                }
            }
        }

        return min(100, max(0, score))
    }

    private static func drainScore(for input: BodyBatteryInput) -> Int {
        var score = 0

        if input.steps2h > 5_000 {
            score += ((input.steps2h - 5_000) / 1_000) * 3
        }

        score += input.activeEnergyKilocalories2h / 35
        score += input.basalEnergyKilocalories2h / 20

        return min(100, max(0, score))
    }

    /// All-day depletion model.
    ///
    /// This is intentionally coarse and scalar-only: the Watch already aggregates today's totals
    /// once during a foreground refresh, then this function applies a few integer divisions. The
    /// model prevents a 16:00 refresh from looking like a new morning by accounting for time awake,
    /// daily active calories, basal calories, and total steps since wake/start of day.
    private static func dailyDrainScore(for input: BodyBatteryInput, baseline: BodyBatteryBaseline?) -> Int {
        var score = 0
        score += max(0, input.awakeMinutesToday) / 45
        score += max(0, input.stepsToday) / 2_500
        score += max(0, input.activeEnergyKilocaloriesToday) / 55
        score += max(0, input.basalEnergyKilocaloriesToday) / 120

        if let baseline {
            if let usualSteps = baseline.stepsToday, usualSteps > 0 {
                let extraSteps = max(0, input.stepsToday - usualSteps)
                score += extraSteps / 1_500
            }
            if let usualActiveEnergy = baseline.activeEnergyKilocaloriesToday, usualActiveEnergy > 0 {
                let extraActiveEnergy = max(0, input.activeEnergyKilocaloriesToday - usualActiveEnergy)
                score += extraActiveEnergy / 75
            }
        }

        return min(100, max(0, score))
    }

    private static func sleepQualityScore(for input: BodyBatteryInput) -> Int {
        guard input.sleepMinutes24h > 0 else { return 0 }

        let totalSleep = max(1, input.sleepMinutes24h)
        let inBedMinutes = max(totalSleep, totalSleep + input.awakeMinutesDuringSleep24h)
        let efficiency = min(100, max(0, totalSleep * 100 / max(1, inBedMinutes)))
        let deepPercent = min(100, max(0, input.deepSleepMinutes24h * 100 / totalSleep))
        let remPercent = min(100, max(0, input.remSleepMinutes24h * 100 / totalSleep))

        var score = 0

        switch totalSleep {
        case ..<240:
            score += 6
        case 240..<330:
            score += 22
        case 330..<(7 * 60):
            score += 32
        case (7 * 60)..<(9 * 60):
            score += 40
        default:
            score += 36
        }

        switch efficiency {
        case ..<75:
            score += 4
        case 75..<85:
            score += 10
        case 85..<92:
            score += 16
        default:
            score += 20
        }

        switch deepPercent {
        case ..<8:
            score += 2
        case 8..<13:
            score += 8
        case 13..<23:
            score += 16
        default:
            score += 12
        }

        switch remPercent {
        case ..<10:
            score += 2
        case 10..<18:
            score += 8
        case 18..<28:
            score += 16
        default:
            score += 12
        }

        if input.awakeMinutesDuringSleep24h > 90 {
            score -= 12
        } else if input.awakeMinutesDuringSleep24h > 50 {
            score -= 6
        }

        return min(100, max(0, score))
    }
}

/// Shared color mapping used by both apps to keep the UI consistent without duplicating thresholds.
public enum BatteryLevelStyle {
    public static func color(for level: Int) -> Color {
        switch level {
        case ...40:
            return .orange
        case 41...70:
            return .yellow
        default:
            return .green
        }
    }
}
