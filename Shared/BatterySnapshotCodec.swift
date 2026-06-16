import Foundation

/// WatchConnectivity 消息与 `BodyBatterySummary` 之间的编解码。
///
/// Watch 与 iPhone 原本各自维护一份几乎相同的 `payload(for:)` / `apply(message:)`。
/// 这里集中两端共用的字段映射，保证传输字段不漂移，并消除重复实现。
public enum BatterySnapshotCodec {
    /// 把摘要编码成 WatchConnectivity 可传输的 `[String: Any]` 字典。
    public static func payload(for summary: BodyBatterySummary) -> [String: Any] {
        var payload: [String: Any] = [
            PayloadKey.level.rawValue: summary.level,
            PayloadKey.stressScore.rawValue: summary.stressScore,
            PayloadKey.recoveryScore.rawValue: summary.recoveryScore,
            PayloadKey.drainScore.rawValue: summary.drainScore,
            PayloadKey.dailyDrainScore.rawValue: summary.dailyDrainScore,
            PayloadKey.fatigueLoadScore.rawValue: summary.fatigueLoadScore,
            PayloadKey.sleepQualityScore.rawValue: summary.sleepQualityScore,
            PayloadKey.steps2h.rawValue: summary.steps2h,
            PayloadKey.activeEnergyKilocalories2h.rawValue: summary.activeEnergyKilocalories2h,
            PayloadKey.basalEnergyKilocalories2h.rawValue: summary.basalEnergyKilocalories2h,
            PayloadKey.awakeMinutesToday.rawValue: summary.awakeMinutesToday,
            PayloadKey.stepsToday.rawValue: summary.stepsToday,
            PayloadKey.activeEnergyKilocaloriesToday.rawValue: summary.activeEnergyKilocaloriesToday,
            PayloadKey.basalEnergyKilocaloriesToday.rawValue: summary.basalEnergyKilocaloriesToday
        ]
        if let hrv = summary.hrvSDNNMilliseconds {
            payload[PayloadKey.hrvSDNNMilliseconds.rawValue] = hrv
        }
        return payload
    }

    /// 从 WatchConnectivity 消息字典解码出摘要。
    /// 缺失电池主值（level）时返回 nil，表示这不是有效的快照消息。
    public static func summary(from message: [String: Any]) -> BodyBatterySummary? {
        guard let level = message[PayloadKey.level.rawValue] as? Int else { return nil }
        return BodyBatterySummary(
            level: level,
            stressScore: message[PayloadKey.stressScore.rawValue] as? Int ?? 0,
            recoveryScore: message[PayloadKey.recoveryScore.rawValue] as? Int ?? 0,
            drainScore: message[PayloadKey.drainScore.rawValue] as? Int ?? 0,
            dailyDrainScore: message[PayloadKey.dailyDrainScore.rawValue] as? Int ?? 0,
            fatigueLoadScore: message[PayloadKey.fatigueLoadScore.rawValue] as? Int ?? 0,
            sleepQualityScore: message[PayloadKey.sleepQualityScore.rawValue] as? Int ?? 0,
            hrvSDNNMilliseconds: message[PayloadKey.hrvSDNNMilliseconds.rawValue] as? Int,
            steps2h: message[PayloadKey.steps2h.rawValue] as? Int ?? 0,
            activeEnergyKilocalories2h: message[PayloadKey.activeEnergyKilocalories2h.rawValue] as? Int ?? 0,
            basalEnergyKilocalories2h: message[PayloadKey.basalEnergyKilocalories2h.rawValue] as? Int ?? 0,
            awakeMinutesToday: message[PayloadKey.awakeMinutesToday.rawValue] as? Int ?? 0,
            stepsToday: message[PayloadKey.stepsToday.rawValue] as? Int ?? 0,
            activeEnergyKilocaloriesToday: message[PayloadKey.activeEnergyKilocaloriesToday.rawValue] as? Int ?? 0,
            basalEnergyKilocaloriesToday: message[PayloadKey.basalEnergyKilocaloriesToday.rawValue] as? Int ?? 0
        )
    }

    /// 消息字典里的"请求 iPhone 快照"标志，两端共用同一个键。
    public static let requestPhoneSnapshotKey = "requestPhoneSnapshot"

    private enum PayloadKey: String {
        case level = "batteryLevel"
        case stressScore
        case recoveryScore
        case drainScore
        case dailyDrainScore
        case fatigueLoadScore
        case sleepQualityScore
        case hrvSDNNMilliseconds
        case steps2h
        case activeEnergyKilocalories2h
        case basalEnergyKilocalories2h
        case awakeMinutesToday
        case stepsToday
        case activeEnergyKilocaloriesToday
        case basalEnergyKilocaloriesToday
    }
}
