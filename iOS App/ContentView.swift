import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectivity: iPhoneConnectivityManager
    @EnvironmentObject private var historyStore: BatteryHistoryStore
    @EnvironmentObject private var onboardingStore: OnboardingStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if onboardingStore.isCompleted {
                TabView {
                    TodayDashboardView()
                        .tabItem { Label("今日", systemImage: "battery.100percent") }

                    WorkoutCalendarView()
                        .tabItem { Label("锻炼", systemImage: "figure.run") }

                    TrendDashboardView()
                        .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }

                    MoreView()
                        .tabItem { Label("更多", systemImage: "ellipsis.circle") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OnboardingView()
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .background(Color.black.ignoresSafeArea())
        .tint(.green)
        .preferredColorScheme(.dark)
        .toolbarBackground(.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct TodayDashboardView: View {
    @EnvironmentObject private var connectivity: iPhoneConnectivityManager
    @EnvironmentObject private var historyStore: BatteryHistoryStore
    @EnvironmentObject private var healthKitManager: iPhoneHealthKitManager

    private var currentSummary: BodyBatterySummary {
        healthKitManager.summary ?? connectivity.summary ?? historyStore.latestSummary ?? .full
    }

    var body: some View {
        AppScreen {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(title: "今日", subtitle: "身体电量详情")

                HStack(alignment: .center, spacing: 20) {
                    BatteryRingView(level: currentSummary.level, size: 178)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("身体电量")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.66))
                        Text("\(currentSummary.level)")
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(healthKitManager.isRefreshing ? "正在读取 Apple 健康..." : connectivity.statusText)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MetricGridView(summary: currentSummary)

                TodayEnergyView(summary: currentSummary)

                Button {
                    Task {
                        if let summary = await healthKitManager.refreshSummary(force: true) {
                            connectivity.publishLocalSummary(summary, source: "Apple 健康已刷新")
                        }
                    }
                } label: {
                    Label(healthKitManager.isRefreshing ? "刷新中" : "刷新健康数据", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(healthKitManager.isRefreshing)
            }
        }
        .task {
            if let summary = await healthKitManager.refreshSummary(force: false) {
                connectivity.publishLocalSummary(summary, source: "Apple 健康快照")
            }
        }
    }
}

private struct WorkoutCalendarView: View {
    @EnvironmentObject private var historyStore: BatteryHistoryStore

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 12)
    ]

    var body: some View {
        AppScreen {
            VStack(alignment: .leading, spacing: 16) {
                HeaderView(title: "锻炼", subtitle: "每日三环完成情况")

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(historyStore.dailySummaries(lastDays: 30)) { day in
                        DayRingsTile(day: day)
                    }
                }
            }
        }
    }
}

private struct TrendDashboardView: View {
    @EnvironmentObject private var historyStore: BatteryHistoryStore
    @State private var selectedRange = TrendRange.sevenDays

    var body: some View {
        AppScreen {
            VStack(alignment: .leading, spacing: 16) {
                HeaderView(title: "趋势", subtitle: "身体电量走线")

                Picker("范围", selection: $selectedRange) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                TrendPanelView(records: historyStore.records(lastDays: selectedRange.days))
                    .frame(height: 260)

                TrendSummaryStrip(records: historyStore.records(lastDays: selectedRange.days))
            }
        }
    }
}

private struct MoreView: View {
    var body: some View {
        AppScreen {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(title: "更多", subtitle: "关于 BodyBattery")

                InfoBlock(
                    title: "本地身体电量",
                    text: "BodyBattery 在 iPhone 端读取 Apple 健康数据并进行本地分析，Watch 端只显示 iPhone 发送的轻量快照。"
                )
                InfoBlock(
                    title: "省电策略",
                    text: "App 不使用网络，不做轮询。健康数据读取由打开 iPhone App 或点击刷新触发，Watch 端不再主动查询 HealthKit。"
                )
                InfoBlock(
                    title: "趋势记录",
                    text: "iPhone 使用本地 AppStorage 保存最近 60 天同步记录，用于展示今日、锻炼和趋势页面。"
                )
            }
        }
    }
}

private struct AppScreen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }
}

private struct HeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricGridView: View {
    let summary: BodyBatterySummary

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            MetricTile(title: "压力", value: "\(summary.stressScore)", tint: .orange)
            MetricTile(title: "恢复", value: "\(summary.recoveryScore)", tint: .green)
            MetricTile(title: "日耗", value: "\(summary.dailyDrainScore)", tint: .red)
            MetricTile(title: "疲劳", value: "\(summary.fatigueLoadScore)", tint: .purple)
            MetricTile(title: "睡眠", value: "\(summary.sleepQualityScore)", tint: .blue)
            MetricTile(title: "HRV", value: summary.hrvSDNNMilliseconds.map { "\($0)ms" } ?? "--", tint: .cyan)
            MetricTile(title: "今日", value: "\(summary.activeEnergyKilocaloriesToday + summary.basalEnergyKilocaloriesToday)kcal", tint: .mint)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TodayEnergyView: View {
    let summary: BodyBatterySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日消耗")
                .font(.headline)
            HStack(spacing: 12) {
                EnergyItem(title: "步数", value: "\(summary.stepsToday)", color: .green)
                EnergyItem(title: "活动", value: "\(summary.activeEnergyKilocaloriesToday)kcal", color: .orange)
                EnergyItem(title: "静息", value: "\(summary.basalEnergyKilocaloriesToday)kcal", color: .blue)
            }
        }
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EnergyItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DayRingsTile: View {
    let day: DailyBatterySummary

    var body: some View {
        VStack(spacing: 8) {
            TripleRingView(
                first: day.stepProgress,
                second: day.energyProgress,
                third: day.batteryProgress,
                size: 58
            )
            Text(day.date, format: .dateTime.month(.defaultDigits).day())
                .font(.caption.weight(.medium))
            Text("\(day.maxSteps) 步")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .padding(10)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TripleRingView: View {
    let first: Double
    let second: Double
    let third: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            progressRing(first, color: .green, lineWidth: 7, inset: 0)
            progressRing(second, color: .orange, lineWidth: 7, inset: 10)
            progressRing(third, color: .cyan, lineWidth: 7, inset: 20)
        }
        .frame(width: size, height: size)
    }

    private func progressRing(_ value: Double, color: Color, lineWidth: CGFloat, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private enum TrendRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case sixtyDays = 60

    var id: Int { rawValue }
    var days: Int { rawValue }
    var title: String {
        switch self {
        case .sevenDays: return "7 天"
        case .thirtyDays: return "30 天"
        case .sixtyDays: return "60 天"
        }
    }
}

struct TrendPanelView: View {
    let records: [BatteryRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                LegendDot(title: "电量", color: .green)
                LegendDot(title: "压力", color: .orange)
                LegendDot(title: "日耗", color: .red)
                LegendDot(title: "睡眠", color: .blue)
                Spacer()
            }
            MultiTrendLineView(records: records)
        }
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("身体电量、压力、日耗和睡眠趋势")
    }
}

struct LegendDot: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

struct MultiTrendLineView: View {
    let records: [BatteryRecord]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HorizontalGridLines()
                trendPath(in: proxy.size, value: { $0.level })
                    .stroke(.green, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                trendPath(in: proxy.size, value: { $0.stressScore })
                    .stroke(.orange, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                trendPath(in: proxy.size, value: { $0.dailyDrainScore })
                    .stroke(.red, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                trendPath(in: proxy.size, value: { $0.sleepQualityScore })
                    .stroke(.blue, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            }
        }
    }

    private func trendPath(in size: CGSize, value: (BatteryRecord) -> Int) -> Path {
        let points = normalizedPoints(in: size, value: value)
        return Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func normalizedPoints(in size: CGSize, value: (BatteryRecord) -> Int) -> [CGPoint] {
        guard !records.isEmpty else { return [] }
        let sorted = records.sorted { $0.date < $1.date }
        guard let firstDate = sorted.first?.date, let lastDate = sorted.last?.date else { return [] }
        let span = max(lastDate.timeIntervalSince(firstDate), 1)
        let drawingHeight = max(size.height, 1)

        return sorted.map { record in
            let x = record.date.timeIntervalSince(firstDate) / span * size.width
            let y = (1 - Double(min(100, max(0, value(record)))) / 100) * drawingHeight
            return CGPoint(x: x, y: y)
        }
    }
}

private struct HorizontalGridLines: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for fraction in [0.25, 0.5, 0.75] {
                    let y = proxy.size.height * fraction
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct TrendSummaryStrip: View {
    let records: [BatteryRecord]

    private var averageLevel: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.level).reduce(0, +) / records.count
    }

    private var lowLevel: Int {
        records.map(\.level).min() ?? 0
    }

    private var highStress: Int {
        records.map(\.stressScore).max() ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            MetricTile(title: "均值", value: "\(averageLevel)", tint: .green)
            MetricTile(title: "低点", value: "\(lowLevel)", tint: .red)
            MetricTile(title: "最高压力", value: "\(highStress)", tint: .orange)
        }
    }
}

struct BatteryRingView: View {
    let level: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: max(10, size * 0.08))
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(
                    BatteryLevelStyle.color(for: level),
                    style: StrokeStyle(lineWidth: max(10, size * 0.08), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Image(systemName: "battery.100percent")
                    .font(.title2)
                Text("\(level)")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }
}

private struct InfoBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
