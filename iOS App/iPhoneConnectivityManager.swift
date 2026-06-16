import Foundation
import WatchConnectivity

@MainActor
final class iPhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var summary: BodyBatterySummary?
    @Published private(set) var statusText = "未同步"

    func activate() {
        guard WCSession.isSupported() else {
            statusText = "当前设备不支持手表通信"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        if !WCSession.default.receivedApplicationContext.isEmpty {
            apply(message: WCSession.default.receivedApplicationContext, source: "已读取最近快照")
        }
    }

    /// Publishes the iPhone-computed HealthKit summary to the paired Watch.
    ///
    /// 省电策略：使用 `updateApplicationContext` 只保留一份最新快照，不维护重试队列。
    /// 身体电量是慢变量，Watch 端无需被频繁实时唤醒；下次连通时系统会交付最新值。
    func publishLocalSummary(_ nextSummary: BodyBatterySummary, source: String) {
        summary = nextSummary
        batteryLevel = nextSummary.level
        statusText = source

        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(BatterySnapshotCodec.payload(for: nextSummary))
    }

    func sendSyncRequest() {
        guard WCSession.isSupported() else {
            statusText = "当前设备不支持手表通信"
            return
        }
        guard WCSession.default.activationState == .activated else {
            statusText = "通信未激活，请稍后再试"
            return
        }
        guard WCSession.default.isPaired else {
            statusText = "没有配对的 Apple Watch"
            return
        }
        guard WCSession.default.isWatchAppInstalled else {
            statusText = "手表端 App 未安装"
            return
        }
        statusText = "正在发送最新快照..."
        let payload = summary.map { BatterySnapshotCodec.payload(for: $0) } ?? [BatterySnapshotCodec.requestPhoneSnapshotKey: true]
        guard WCSession.default.isReachable else {
            statusText = "手表未前台，已保存最新快照"
            if let summary {
                try? WCSession.default.updateApplicationContext(BatterySnapshotCodec.payload(for: summary))
            }
            return
        }
        WCSession.default.sendMessage(payload) { [weak self] reply in
            Task { @MainActor in
                self?.apply(message: reply, source: "手表已确认")
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.statusText = "快照发送失败 \(Self.shortError(error))"
            }
        }
    }

    private func apply(message: [String: Any], source: String) {
        guard let nextSummary = BatterySnapshotCodec.summary(from: message) else { return }
        summary = nextSummary
        batteryLevel = nextSummary.level
        statusText = source
    }

    nonisolated private static func shortError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}

extension iPhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error {
                self.statusText = "通信激活失败 \(Self.shortError(error))"
            } else if !session.receivedApplicationContext.isEmpty {
                self.apply(message: session.receivedApplicationContext, source: "已读取最近快照")
            } else {
                self.statusText = activationState == .activated ? "通信已就绪" : "通信未就绪"
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message: message, source: "收到手表更新")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if message[BatterySnapshotCodec.requestPhoneSnapshotKey] as? Bool == true, let summary = self.summary {
                replyHandler(BatterySnapshotCodec.payload(for: summary))
            } else {
                self.apply(message: message, source: "收到手表更新")
                replyHandler(self.summary.map { BatterySnapshotCodec.payload(for: $0) } ?? [:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(message: applicationContext, source: "收到手表快照")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            self.apply(message: userInfo, source: "后台同步成功")
        }
    }
}
