import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var healthKitManager: iPhoneHealthKitManager

    @State private var step = 0
    @State private var profile = OnboardingProfile()
    @State private var analysisProgress = 0.0
    @State private var draftGoals: [UserGoal] = []
    @State private var editingGoal: UserGoal?
    @State private var didRequestHealth = false
    @State private var didRequestNotifications = false

    private let totalSteps = 12

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(.green)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                TabView(selection: $step) {
                    permissionIntro.tag(0)
                    choiceStep(
                        title: "你最希望 BodyBattery 关注什么？",
                        subtitle: "这会影响初始目标和首页优先展示的数据。",
                        choices: [.bodyBattery, .training, .curiosity, .friends],
                        selection: $profile.primaryInterest
                    ).tag(1)
                    birthdayStep.tag(2)
                    heartZoneStep.tag(3)
                    choiceStep(
                        title: "你希望改善的是？",
                        subtitle: "选择一个当前最重要的方向。",
                        choices: [.fitness, .stress, .sleep, .overall],
                        selection: $profile.improvement
                    ).tag(4)
                    choiceStep(
                        title: "阻碍你进步的是？",
                        subtitle: "目标会尽量从这个阻碍开始变得更容易执行。",
                        choices: [.noTime, .noPlan, .hardToKeep, .none],
                        selection: $profile.blocker
                    ).tag(5)
                    choiceStep(
                        title: "你最近的活跃度是？",
                        subtitle: "用于估算步数和活动能量目标。",
                        choices: [.sedentary, .light, .moderate, .veryActive],
                        selection: $profile.activity
                    ).tag(6)
                    choiceStep(
                        title: "你了解 HRV 吗？",
                        subtitle: "我们会据此调整说明文字的深浅。",
                        choices: [.hrvExpert, .hrvHeard, .hrvNew, .hrvExplain],
                        selection: $profile.hrvKnowledge
                    ).tag(7)
                    choiceStep(
                        title: "你佩戴 Apple Watch 吗？",
                        subtitle: "佩戴习惯会影响身体电量数据的新鲜度。",
                        choices: [.watchDaily, .watchMostDays, .watchWorkout, .watchSometimes, .watchNever],
                        selection: $profile.watchUsage
                    ).tag(8)
                    notificationStep.tag(9)
                    healthConnectStep.tag(10)
                    analysisStep.tag(11)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: step)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            profile = onboardingStore.profile
            draftGoals = OnboardingStore.defaultGoals(for: profile)
        }
        .onChange(of: step) { _, newStep in
            if newStep == 11 {
                runAnalysis()
            }
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditView(goal: goal) { updated in
                if let index = draftGoals.firstIndex(where: { $0.id == updated.id }) {
                    draftGoals[index] = updated
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var permissionIntro: some View {
        OnboardingPage(title: "欢迎使用 BodyBattery", subtitle: "我们会在本地分析 Apple 健康数据，生成身体电量、压力、睡眠和活动目标。") {
            VStack(spacing: 14) {
                OnboardingFeatureRow(symbol: "heart.text.square", title: "健康权限", text: "只读取心率、HRV、睡眠、步数和能量数据。")
                OnboardingFeatureRow(symbol: "lock.shield", title: "本地处理", text: "不使用网络，不上传个人健康数据。")
                OnboardingFeatureRow(symbol: "applewatch", title: "更省电", text: "后续会优先从 iPhone 健康中心读取数据，Watch 只显示快照。")
            }
        }
    }

    private var birthdayStep: some View {
        OnboardingPage(title: "请选择生日", subtitle: "我们用年龄估算心率训练区间。") {
            DatePicker("生日", selection: $profile.birthday, in: birthdayRange, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var heartZoneStep: some View {
        OnboardingPage(title: "你的心率区间", subtitle: "基于年龄估算，后续可随着真实训练数据继续优化。") {
            VStack(spacing: 10) {
                ForEach(OnboardingStore.heartRateZones(age: age)) { zone in
                    HStack {
                        Text(zone.title)
                            .font(.headline)
                        Spacer()
                        Text("\(zone.lower)-\(zone.upper) bpm")
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    .padding(14)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var notificationStep: some View {
        OnboardingPage(title: "开启通知", subtitle: "用于提醒你查看身体电量变化、喝水、活动和睡眠目标。") {
            VStack(spacing: 14) {
                OnboardingFeatureRow(symbol: "bell.badge", title: "通知提醒", text: healthKitManager.notificationStatusText)
                Button {
                    Task {
                        await healthKitManager.requestNotificationAuthorization()
                        didRequestNotifications = true
                    }
                } label: {
                    Label(didRequestNotifications ? "已处理通知权限" : "开启通知", systemImage: "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var healthConnectStep: some View {
        OnboardingPage(title: "连接 Apple 健康", subtitle: "继续后会打开系统健康数据访问窗口。") {
            VStack(spacing: 14) {
                OnboardingFeatureRow(symbol: "heart.circle", title: "Apple 健康", text: healthKitManager.healthStatusText)
                Button {
                    Task {
                        await healthKitManager.requestHealthAuthorization()
                        didRequestHealth = true
                    }
                } label: {
                    Label(didRequestHealth ? "已处理健康权限" : "连接 Apple 健康", systemImage: "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var analysisStep: some View {
        OnboardingPage(title: analysisProgress < 1 ? "正在分析你的目标" : "推荐目标", subtitle: analysisProgress < 1 ? "根据年龄、活跃度和目标偏好生成初始计划。" : "每张卡片都可以点进去修改。") {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView(value: analysisProgress)
                    .tint(.green)
                Text("\(Int(analysisProgress * 100))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(draftGoals) { goal in
                        Button {
                            editingGoal = goal
                        } label: {
                            GoalCard(goal: goal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(analysisProgress >= 1 ? 1 : 0.35)
            }
        }
    }

    private func choiceStep(title: String, subtitle: String, choices: [OnboardingChoice], selection: Binding<OnboardingChoice>) -> some View {
        OnboardingPage(title: title, subtitle: subtitle) {
            VStack(spacing: 10) {
                ForEach(choices) { choice in
                    Button {
                        selection.wrappedValue = choice
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selection.wrappedValue == choice ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.wrappedValue == choice ? .green : .white.opacity(0.46))
                            Text(choice.rawValue)
                                .font(.headline)
                            Spacer()
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity)
                        .background(selection.wrappedValue == choice ? .green.opacity(0.18) : .white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    step -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.bordered)
            }

            Button {
                advance()
            } label: {
                Text(step == 11 ? "完成" : "继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(step == 11 && analysisProgress < 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }

    private var age: Int {
        max(13, Calendar.current.dateComponents([.year], from: profile.birthday, to: Date()).year ?? 30)
    }

    private var birthdayRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 1930, month: 1, day: 1)) ?? Date()
        let end = calendar.date(byAdding: .year, value: -13, to: Date()) ?? Date()
        return start...end
    }

    private func advance() {
        if step < 11 {
            step += 1
        } else {
            onboardingStore.complete(with: profile, goals: draftGoals)
        }
    }

    private func runAnalysis() {
        analysisProgress = 0
        draftGoals = OnboardingStore.defaultGoals(for: profile)
        Task {
            for index in 1...20 {
                try? await Task.sleep(nanoseconds: 45_000_000)
                await MainActor.run {
                    analysisProgress = Double(index) / 20
                }
            }
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .padding(.top, 22)
        }
        .foregroundStyle(.white)
    }
}

private struct OnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
            }
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GoalCard: View {
    let goal: UserGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: goal.symbolName)
                .font(.title2)
                .foregroundStyle(.green)
            Text(goal.title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
            Text(goal.displayValue)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GoalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var goal: UserGoal
    let onSave: (UserGoal) -> Void

    init(goal: UserGoal, onSave: @escaping (UserGoal) -> Void) {
        self._goal = State(initialValue: goal)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("修改您的目标") {
                    Stepper(value: $goal.value, in: 1...100_000, step: stepSize) {
                        HStack {
                            Text(goal.title)
                            Spacer()
                            Text(goal.displayValue)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(goal.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(goal)
                        dismiss()
                    }
                }
            }
        }
    }

    private var stepSize: Int {
        switch goal.id {
        case "steps": return 500
        case "calories": return 25
        case "sunlight": return 5
        default: return 1
        }
    }
}
