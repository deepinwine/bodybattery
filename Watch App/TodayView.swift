import SwiftUI

struct TodayView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    private var summary: BodyBatterySummary {
        connectivity.latestSummary
    }

    var body: some View {
        VStack(spacing: 10) {
            if !connectivity.hasReceivedSnapshot {
                emptyState
            } else if isLuminanceReduced {
                Text("\(summary.level)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BatteryLevelStyle.color(for: summary.level))
            } else {
                chargedContent
            }
        }
        .padding()
    }

    /// 没有收到任何 iPhone 快照时的占位：避免直接显示"100 满电"误导用户。
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("等待 iPhone")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("打开 iPhone 上的 BodyBattery 刷新一次，手表会自动收到最新身体电量。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
            Button {
                connectivity.requestPhoneSnapshot()
            } label: {
                Label("立即同步", systemImage: "arrow.clockwise")
            }
            .font(.footnote)
        }
    }

    private var chargedContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.25), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(summary.level) / 100)
                    .stroke(
                        BatteryLevelStyle.color(for: summary.level),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Image(systemName: "battery.100percent")
                        .font(.title3)
                    Text("\(summary.level)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.primary)
            }
            .frame(width: 118, height: 118)

            HStack(spacing: 8) {
                WatchMetric(title: "压", value: "\(summary.stressScore)", color: .orange)
                WatchMetric(title: "眠", value: "\(summary.sleepQualityScore)", color: .blue)
                WatchMetric(title: "疲", value: "\(summary.fatigueLoadScore)", color: .red)
            }

            Button {
                connectivity.requestPhoneSnapshot()
            } label: {
                Label("同步", systemImage: "arrow.clockwise")
            }
            .font(.footnote)

            Text(connectivity.statusText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct WatchMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 42, height: 28)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
