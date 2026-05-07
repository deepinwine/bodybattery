import SwiftUI

struct TodayView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    private var summary: BodyBatterySummary {
        connectivity.latestSummary
    }

    var body: some View {
        VStack(spacing: 10) {
            if isLuminanceReduced {
                Text("\(summary.level)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BatteryLevelStyle.color(for: summary.level))
            } else {
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
                    WatchMetric(title: "日耗", value: "\(summary.dailyDrainScore)", color: .red)
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
        .padding()
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
