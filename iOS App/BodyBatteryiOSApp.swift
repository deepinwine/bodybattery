import SwiftUI

@main
struct BodyBatteryiOSApp: App {
    @StateObject private var connectivity = iPhoneConnectivityManager()
    @StateObject private var historyStore = BatteryHistoryStore()
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var healthKitManager = iPhoneHealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
                .environmentObject(historyStore)
                .environmentObject(onboardingStore)
                .environmentObject(healthKitManager)
                .onReceive(connectivity.$summary.compactMap { $0 }) { summary in
                    historyStore.append(summary: summary)
                }
                .task {
                    connectivity.activate()
                    historyStore.seedDebugDataIfNeeded()
                }
        }
    }
}
