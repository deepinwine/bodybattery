import XCTest
@testable import BodyBatteryShared

final class BodyBatteryCalculatorTests: XCTestCase {
    func testNoDataReturnsFullBattery() {
        let input = BodyBatteryInput()

        XCTAssertEqual(BodyBatteryCalculator.calculate(input), 100)
    }

    func testHighHeartRateDeductsStressPoints() {
        let input = BodyBatteryInput(restingHeartRate: 60, averageHeartRate2h: 112)

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertEqual(summary.stressScore, 50)
        XCTAssertEqual(summary.level, 50)
    }

    func testLargeStepCountDeductsActivityPoints() {
        let input = BodyBatteryInput(steps2h: 8_200)

        XCTAssertEqual(BodyBatteryCalculator.calculate(input), 91)
    }

    func testLongSleepAddsRecoveryButClampsAtOneHundred() {
        let input = BodyBatteryInput(restingHeartRate: 70, averageHeartRate2h: 75, sleepMinutes24h: 480)

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.recoveryScore, 10)
        XCTAssertEqual(BodyBatteryCalculator.calculate(input), 100)
    }

    func testIdealHRVAddsRecovery() {
        let input = BodyBatteryInput(restingHeartRate: 70, averageHeartRate2h: 75, hrvSDNNMilliseconds: 55)

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertEqual(summary.recoveryScore, 16)
        XCTAssertEqual(BodyBatteryCalculator.calculate(input), 100)
    }

    func testLowHRVAndElevatedHeartRateIncreaseStressScore() {
        let input = BodyBatteryInput(restingHeartRate: 60, averageHeartRate2h: 95, hrvSDNNMilliseconds: 25)

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.stressScore, 45)
        XCTAssertLessThan(summary.level, 100)
    }

    func testActiveAndBasalEnergyIncreaseDrainScore() {
        let input = BodyBatteryInput(steps2h: 7_500, activeEnergyKilocalories2h: 450, basalEnergyKilocalories2h: 90)

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.drainScore, 18)
    }

    func testStrongSleepAndHRVIncreaseRecoveryScore() {
        let input = BodyBatteryInput(
            restingHeartRate: 58,
            averageHeartRate2h: 66,
            hrvSDNNMilliseconds: 58,
            sleepMinutes24h: 510
        )

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.recoveryScore, 18)
        XCTAssertEqual(summary.level, 100)
    }

    func testPoorSleepQualityPreventsHighBatteryDespiteLongSleep() {
        let input = BodyBatteryInput(
            restingHeartRate: 62,
            averageHeartRate2h: 70,
            hrvSDNNMilliseconds: 32,
            sleepMinutes24h: 500,
            deepSleepMinutes24h: 20,
            remSleepMinutes24h: 35,
            awakeMinutesDuringSleep24h: 95
        )

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertLessThanOrEqual(summary.sleepQualityScore, 45)
        XCTAssertGreaterThanOrEqual(summary.stressScore, 20)
        XCTAssertLessThan(summary.level, 90)
    }

    func testGoodSleepStagesIncreaseSleepQualityAndRecovery() {
        let input = BodyBatteryInput(
            restingHeartRate: 58,
            averageHeartRate2h: 64,
            hrvSDNNMilliseconds: 56,
            sleepMinutes24h: 500,
            deepSleepMinutes24h: 95,
            remSleepMinutes24h: 105,
            awakeMinutesDuringSleep24h: 25
        )

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.sleepQualityScore, 80)
        XCTAssertGreaterThanOrEqual(summary.recoveryScore, 25)
        XCTAssertEqual(summary.level, 100)
    }

    func testShortSleepMeaningfullyReducesBattery() {
        let input = BodyBatteryInput(
            restingHeartRate: 60,
            averageHeartRate2h: 68,
            hrvSDNNMilliseconds: 42,
            sleepMinutes24h: 210,
            deepSleepMinutes24h: 30,
            remSleepMinutes24h: 35,
            awakeMinutesDuringSleep24h: 40
        )

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertLessThanOrEqual(summary.sleepQualityScore, 40)
        XCTAssertLessThan(summary.level, 90)
    }

    func testLateDayAwakeHoursAndDailyEnergyReduceBattery() {
        let input = BodyBatteryInput(
            restingHeartRate: 58,
            averageHeartRate2h: 68,
            hrvSDNNMilliseconds: 55,
            sleepMinutes24h: 500,
            deepSleepMinutes24h: 90,
            remSleepMinutes24h: 100,
            awakeMinutesDuringSleep24h: 25,
            steps2h: 1_200,
            activeEnergyKilocalories2h: 70,
            basalEnergyKilocalories2h: 75,
            awakeMinutesToday: 600,
            stepsToday: 7_000,
            activeEnergyKilocaloriesToday: 420,
            basalEnergyKilocaloriesToday: 1_050
        )

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.dailyDrainScore, 30)
        XCTAssertLessThan(summary.level, 75)
    }

    func testMorningAfterGoodSleepStartsHighBeforeDailyDrain() {
        let input = BodyBatteryInput(
            restingHeartRate: 58,
            averageHeartRate2h: 62,
            hrvSDNNMilliseconds: 58,
            sleepMinutes24h: 510,
            deepSleepMinutes24h: 95,
            remSleepMinutes24h: 105,
            awakeMinutesDuringSleep24h: 20,
            awakeMinutesToday: 45,
            stepsToday: 300,
            activeEnergyKilocaloriesToday: 20,
            basalEnergyKilocaloriesToday: 80
        )

        let summary = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThanOrEqual(summary.level, 85)
    }

    func testCalculationCompletesUnderFiveMilliseconds() {
        let input = BodyBatteryInput(
            restingHeartRate: 58,
            averageHeartRate2h: 104,
            hrvSDNNMilliseconds: 52,
            sleepMinutes24h: 510,
            steps2h: 7_400,
            activeEnergyKilocalories2h: 180,
            basalEnergyKilocalories2h: 80
        )

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<1_000 {
                _ = BodyBatteryCalculator.calculate(input)
            }
        }

        let start = ContinuousClock.now
        _ = BodyBatteryCalculator.summarize(input)
        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed.components.attoseconds, 5_000_000_000_000_000)
    }

    func testPersonalBaselineRewardsBetterThanUsualRecoverySignals() {
        let baseline = BodyBatteryBaseline(
            restingHeartRate: 62,
            hrvSDNNMilliseconds: 44,
            sleepQualityScore: 68,
            sleepMinutes: 430,
            stepsToday: 8_000,
            activeEnergyKilocaloriesToday: 420
        )
        let input = BodyBatteryInput(
            restingHeartRate: 56,
            averageHeartRate2h: 60,
            hrvSDNNMilliseconds: 58,
            sleepMinutes24h: 500,
            deepSleepMinutes24h: 95,
            remSleepMinutes24h: 100,
            awakeMinutesDuringSleep24h: 18,
            awakeMinutesToday: 90,
            stepsToday: 800,
            activeEnergyKilocaloriesToday: 45,
            basalEnergyKilocaloriesToday: 160
        )

        let personalized = BodyBatteryCalculator.summarize(input, baseline: baseline)
        let generic = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThan(personalized.recoveryScore, generic.recoveryScore)
        XCTAssertLessThanOrEqual(personalized.stressScore, generic.stressScore)
        XCTAssertGreaterThanOrEqual(personalized.level, generic.level)
    }

    func testPersonalBaselinePenalizesLowHRVAndElevatedRestingHeartRate() {
        let baseline = BodyBatteryBaseline(
            restingHeartRate: 56,
            hrvSDNNMilliseconds: 62,
            sleepQualityScore: 82,
            sleepMinutes: 500,
            stepsToday: 7_000,
            activeEnergyKilocaloriesToday: 380
        )
        let input = BodyBatteryInput(
            restingHeartRate: 69,
            averageHeartRate2h: 86,
            hrvSDNNMilliseconds: 34,
            sleepMinutes24h: 430,
            deepSleepMinutes24h: 35,
            remSleepMinutes24h: 45,
            awakeMinutesDuringSleep24h: 85,
            awakeMinutesToday: 540,
            stepsToday: 4_000,
            activeEnergyKilocaloriesToday: 180,
            basalEnergyKilocaloriesToday: 850
        )

        let personalized = BodyBatteryCalculator.summarize(input, baseline: baseline)
        let generic = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThan(personalized.stressScore, generic.stressScore)
        XCTAssertLessThan(personalized.level, generic.level)
    }

    func testDailyDrainUsesActivityAbovePersonalBaseline() {
        let baseline = BodyBatteryBaseline(
            restingHeartRate: 60,
            hrvSDNNMilliseconds: 50,
            sleepQualityScore: 72,
            sleepMinutes: 460,
            stepsToday: 6_500,
            activeEnergyKilocaloriesToday: 350
        )
        let input = BodyBatteryInput(
            restingHeartRate: 60,
            averageHeartRate2h: 72,
            hrvSDNNMilliseconds: 48,
            sleepMinutes24h: 460,
            deepSleepMinutes24h: 75,
            remSleepMinutes24h: 90,
            awakeMinutesDuringSleep24h: 30,
            steps2h: 3_200,
            activeEnergyKilocalories2h: 220,
            basalEnergyKilocalories2h: 80,
            awakeMinutesToday: 720,
            stepsToday: 15_500,
            activeEnergyKilocaloriesToday: 920,
            basalEnergyKilocaloriesToday: 1_250
        )

        let personalized = BodyBatteryCalculator.summarize(input, baseline: baseline)
        let generic = BodyBatteryCalculator.summarize(input)

        XCTAssertGreaterThan(personalized.dailyDrainScore, generic.dailyDrainScore)
        XCTAssertLessThan(personalized.level, generic.level)
    }
}
