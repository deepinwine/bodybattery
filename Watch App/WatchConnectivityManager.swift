import Foundation
import WatchConnectivity

/// Watch 端 WatchConnectivity 管理器。
///
/// Watch 端不再读取 HealthKit，只接收 iPhone 发来的轻量身体电量快照并展示。
/// 这里只保留"接收应用上下文 / 应答 sendMessage / 主动请求 iPhone 快照"三条路径，
/// 不维护发送队列、不缓存待发摘要——Watch 不产生摘要。
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var latestSummary: BodyBatterySummary = .full
    @Published private(set) var hasReceivedSnapshot = false
    @Published private(set) var statusText = "等待 iPhone 快照"

    func configure() {
        guard WCSession.isSupported() else {
            statusText = "当前设备不支持通信"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        if !WCSession.default.receivedApplicationContext.isEmpty {
            apply(message: WCSession.default.receivedApplicationContext, source: "已读取 iPhone 快照")
        }
    }

    /// 请求 iPhone 立即回送最新快照。iPhone 必须 reachable 才能成功。
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
        WCSession.default.sendMessage([BatterySnapshotCodec.requestPhoneSnapshotKey: true]) { [weak self] reply in
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
        guard let summary = BatterySnapshotCodec.summary(from: message) else { return }
        latestSummary = summary
        hasReceivedSnapshot = true
        statusText = source
    }

    nonisolated private static func shortError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
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
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.apply(message: message, source: "收到 iPhone 快照")
            replyHandler(BatterySnapshotCodec.payload(for: self.latestSummary))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(message: applicationContext, source: "收到 iPhone 快照")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // 旧版本曾用 transferUserInfo 做后台同步兜底，这些条目可能延迟批量到达。
        // 当前 Watch 只在前台接收快照，忽略历史 userInfo 避免无谓的后台唤醒。
    }
}
