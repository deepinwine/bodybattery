import Foundation
import SwiftUI

enum OnboardingChoice: String, CaseIterable, Identifiable, Codable {
    case bodyBattery = "HRV / 压力 / 身体电量"
    case training = "锻炼"
    case curiosity = "好奇"
    case friends = "和好友互动"
    case fitness = "健身"
    case stress = "缓解压力"
    case sleep = "优化睡眠"
    case overall = "总体健康"
    case noTime = "没时间"
    case noPlan = "没计划"
    case hardToKeep = "难坚持"
    case none = "以上都不是"
    case sedentary = "不咋动"
    case light = "轻度运动"
    case moderate = "中等活跃"
    case veryActive = "非常活跃"
    case hrvExpert = "我很了解"
    case hrvHeard = "我听说过"
    case hrvNew = "不太懂"
    case hrvExplain = "完全不懂，跟我讲讲"
    case watchDaily = "天天戴"
    case watchMostDays = "经常戴"
    case watchWorkout = "运动时戴"
    case watchSometimes = "偶尔戴"
    case watchNever = "完全没有"

    var id: String { rawValue }
}

struct HeartRateZone: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let lower: Int
    let upper: Int
}

struct UserGoal: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var value: Int
    var unit: String
    var symbolName: String

    var displayValue: String {
        "\(value)\(unit)"
    }
}

struct OnboardingProfile: Codable, Equatable {
    var primaryInterest: OnboardingChoice = .bodyBattery
    var birthday: Date = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? Date()
    var improvement: OnboardingChoice = .overall
    var blocker: OnboardingChoice = .noTime
    var activity: OnboardingChoice = .light
    var hrvKnowledge: OnboardingChoice = .hrvHeard
    var watchUsage: OnboardingChoice = .watchDaily
}

@MainActor
final class OnboardingStore: ObservableObject {
    @AppStorage("onboarding.completed") private var completedStorage = false
    @AppStorage("onboarding.profile") private var profileStorage = ""
    @AppStorage("onboarding.goals") private var goalsStorage = ""

    @Published var profile: OnboardingProfile
    @Published var goals: [UserGoal]

    var isCompleted: Bool {
        get { completedStorage }
        set { completedStorage = newValue }
    }

    init() {
        let defaults = UserDefaults.standard
        let storedProfile = defaults.string(forKey: "onboarding.profile") ?? ""
        let storedGoals = defaults.string(forKey: "onboarding.goals") ?? ""
        let decodedProfile = Self.decode(OnboardingProfile.self, from: storedProfile) ?? OnboardingProfile()
        self.profile = decodedProfile
        self.goals = Self.decode([UserGoal].self, from: storedGoals) ?? Self.defaultGoals(for: decodedProfile)
    }

    func saveProfile(_ profile: OnboardingProfile) {
        self.profile = profile
        profileStorage = Self.encode(profile)
    }

    func complete(with profile: OnboardingProfile, goals: [UserGoal]? = nil) {
        saveProfile(profile)
        self.goals = goals ?? Self.defaultGoals(for: profile)
        goalsStorage = Self.encode(self.goals)
        completedStorage = true
    }

    func updateGoal(_ goal: UserGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal
        goalsStorage = Self.encode(goals)
    }

    func heartRateZones(for birthday: Date? = nil) -> [HeartRateZone] {
        Self.heartRateZones(age: Self.age(from: birthday ?? profile.birthday))
    }

    static func defaultGoals(for profile: OnboardingProfile) -> [UserGoal] {
        let activityBonus: Int
        switch profile.activity {
        case .sedentary: activityBonus = 0
        case .light: activityBonus = 1_000
        case .moderate: activityBonus = 2_000
        case .veryActive: activityBonus = 3_000
        default: activityBonus = 1_000
        }

        return [
            UserGoal(id: "steps", title: "每日步数", value: 7_000 + activityBonus, unit: "步", symbolName: "figure.walk"),
            UserGoal(id: "sleep", title: "睡眠时间", value: 8, unit: "小时", symbolName: "moon.zzz"),
            UserGoal(id: "calories", title: "活动消耗", value: 360 + activityBonus / 20, unit: "kcal", symbolName: "flame"),
            UserGoal(id: "water", title: "喝水", value: 8, unit: "杯", symbolName: "drop"),
            UserGoal(id: "rings", title: "活动圆环", value: 3, unit: "环", symbolName: "circle.hexagongrid"),
            UserGoal(id: "sunlight", title: "晒太阳", value: 20, unit: "分钟", symbolName: "sun.max")
        ]
    }

    static func heartRateZones(age: Int) -> [HeartRateZone] {
        let maxHeartRate = max(120, 220 - age)
        return [
            zone("warmup", "热身", maxHeartRate, 50, 60),
            zone("fat", "燃脂", maxHeartRate, 60, 70),
            zone("aerobic", "有氧健身", maxHeartRate, 70, 85),
            zone("peak", "峰值极限", maxHeartRate, 85, 95)
        ]
    }

    private static func zone(_ id: String, _ title: String, _ maxHeartRate: Int, _ lower: Int, _ upper: Int) -> HeartRateZone {
        HeartRateZone(id: id, title: title, lower: maxHeartRate * lower / 100, upper: maxHeartRate * upper / 100)
    }

    private static func age(from birthday: Date) -> Int {
        max(13, Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 30)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
