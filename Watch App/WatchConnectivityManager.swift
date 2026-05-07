import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    private var refreshHandler: (() async -> Void)?
    @Published private(set) var latestSummary: BodyBatterySummary = .full
    @Published private(set) var statusText = "等待 iPhone 快照"
    private var lastSentSummary: BodyBatterySummary?
    private var cachedSummary: BodyBatterySummary?

    func configure(refreshHandler: @escaping () async -> Void) {
        self.refreshHandler = refreshHandler
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        if !WCSession.default.receivedApplicationContext.isEmpty {
            apply(message: WCSession.default.receivedApplicationContext, source: "已读取 iPhone 快照")
        }
    }

    func sendSummaryIfNeeded(_ summary: BodyBatterySummary) {
        sendSummary(summary, force: false)
    }

    func updateLatestSummary(_ summary: BodyBatterySummary) {
        latestSummary = summary
    }

    func sendSummary(_ summary: BodyBatterySummary, force: Bool) {
        latestSummary = summary
        guard force || shouldSend(summary) else { return }
        send(summary)
    }

    private func shouldSend(_ summary: BodyBatterySummary) -> Bool {
        guard let previous = lastSentSummary else { return true }
        return abs(previous.level - summary.level) > 1 ||
            abs(previous.stressScore - summary.stressScore) > 1 ||
            abs(previous.recoveryScore - summary.recoveryScore) > 1 ||
            abs(previous.drainScore - summary.drainScore) > 1 ||
            abs(previous.dailyDrainScore - summary.dailyDrainScore) > 1 ||
            abs(previous.fatigueLoadScore - summary.fatigueLoadScore) > 1 ||
            abs((previous.hrvSDNNMilliseconds ?? 0) - (summary.hrvSDNNMilliseconds ?? 0)) > 1
    }

    private func send(_ summary: BodyBatterySummary) {
        let payload = Self.payload(for: summary)
        // Watch -> iPhone 只发布最新快照，不主动 sendMessage。sendMessage 会要求两端建立
        // 实时通信通道；对身体电量这种慢变量没有必要，真机长时间佩戴时应优先减少通信唤醒。
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            lastSentSummary = summary
            cachedSummary = nil
        } else {
            // Keep only the latest summary. Avoiding a retry queue prevents repeated background wakeups.
            cachedSummary = summary
        }
    }

    private func flushCachedSummaryIfReachable() {
        guard let cachedSummary, WCSession.default.isReachable else { return }
        send(cachedSummary)
    }

    func requestPhoneSnapshot() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            statusText = "通信未就绪"
            return
        }
        guard WCSession.default.isReachable else {
            statusText = "请打开 iPhone App 刷新"
            return
        }
        statusText = "正在请求 iPhone..."
        WCSession.default.sendMessage(["requestPhoneSnapshot": true]) { [weak self] reply in
            Task { @MainActor in
                self?.apply(message: reply, source: "iPhone 快照已同步")
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.statusText = "同步失败 \(Self.shortError(error))"
            }
        }
    }

    private func apply(message: [String: Any], source: String) {
        guard let level = message["batteryLevel"] as? Int else { return }
        latestSummary = BodyBatterySummary(
            level: level,
            stressScore: message["stressScore"] as? Int ?? 0,
            recoveryScore: message["recoveryScore"] as? Int ?? 0,
            drainScore: message["drainScore"] as? Int ?? 0,
            dailyDrainScore: message["dailyDrainScore"] as? Int ?? 0,
            fatigueLoadScore: message["fatigueLoadScore"] as? Int ?? 0,
            sleepQualityScore: message["sleepQualityScore"] as? Int ?? 0,
            hrvSDNNMilliseconds: message["hrvSDNNMilliseconds"] as? Int,
            steps2h: message["steps2h"] as? Int ?? 0,
            activeEnergyKilocalories2h: message["activeEnergyKilocalories2h"] as? Int ?? 0,
            basalEnergyKilocalories2h: message["basalEnergyKilocalories2h"] as? Int ?? 0,
            awakeMinutesToday: message["awakeMinutesToday"] as? Int ?? 0,
            stepsToday: message["stepsToday"] as? Int ?? 0,
            activeEnergyKilocaloriesToday: message["activeEnergyKilocaloriesToday"] as? Int ?? 0,
            basalEnergyKilocaloriesToday: message["basalEnergyKilocaloriesToday"] as? Int ?? 0
        )
        statusText = source
    }

    nonisolated private static func shortError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    private static func payload(for summary: BodyBatterySummary) -> [String: Any] {
        var payload: [String: Any] = [
            "batteryLevel": summary.level,
            "stressScore": summary.stressScore,
            "recoveryScore": summary.recoveryScore,
            "drainScore": summary.drainScore,
            "dailyDrainScore": summary.dailyDrainScore,
            "fatigueLoadScore": summary.fatigueLoadScore,
            "sleepQualityScore": summary.sleepQualityScore,
            "steps2h": summary.steps2h,
            "activeEnergyKilocalories2h": summary.activeEnergyKilocalories2h,
            "basalEnergyKilocalories2h": summary.basalEnergyKilocalories2h,
            "awakeMinutesToday": summary.awakeMinutesToday,
            "stepsToday": summary.stepsToday,
            "activeEnergyKilocaloriesToday": summary.activeEnergyKilocaloriesToday,
            "basalEnergyKilocaloriesToday": summary.basalEnergyKilocaloriesToday
        ]
        if let hrv = summary.hrvSDNNMilliseconds {
            payload["hrvSDNNMilliseconds"] = hrv
        }
        return payload
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error {
                self.statusText = "通信失败 \(Self.shortError(error))"
            } else if !session.receivedApplicationContext.isEmpty {
                self.apply(message: session.receivedApplicationContext, source: "已读取 iPhone 快照")
            } else {
                self.statusText = activationState == .activated ? "等待 iPhone 快照" : "通信未就绪"
            }
            self.flushCachedSummaryIfReachable()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.flushCachedSummaryIfReachable() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.apply(message: message, source: "收到 iPhone 快照")
            replyHandler(Self.payload(for: self.latestSummary))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(message: applicationContext, source: "收到 iPhone 快照")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Intentionally ignore queued background requests. Older builds used transferUserInfo for
        // sync fallbacks, and those items can be delivered later in batches. Replying to them would
        // create avoidable background traffic and may wake the Watch app after the user stops using
        // it. Foreground sendMessage still returns the latest snapshot immediately.
    }
}
