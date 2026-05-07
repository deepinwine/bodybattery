import SwiftUI

@main
struct BodyBatteryWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connectivity = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environmentObject(connectivity)
                .task {
                    connectivity.configure(refreshHandler: {
                        // Watch 端现在只显示 iPhone 计算出的快照。这里不读 HealthKit，
                        // 避免手表进程因为 iPhone 同步请求而执行健康数据库查询。
                    })
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                connectivity.requestPhoneSnapshot()
            case .background:
                break
            default:
                break
            }
        }
    }
}
