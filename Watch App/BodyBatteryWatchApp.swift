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
                    // Watch 端只显示 iPhone 计算出的快照，不读取 HealthKit，
                    // 避免手表进程因同步请求而执行健康数据库查询。
                    connectivity.configure()
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
