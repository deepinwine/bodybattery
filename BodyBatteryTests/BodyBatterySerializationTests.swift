import XCTest
@testable import BodyBatteryShared

final class BodyBatterySerializationTests: XCTestCase {

    // MARK: - BodyBatterySummary clamp

    func testSummaryClampsScoresIntoZeroToOneHundred() {
        let summary = BodyBatterySummary(
            level: 150,
            stressScore: -20,
            recoveryScore: 200,
            drainScore: 999,
            dailyDrainScore: -5,
            fatigueLoadScore: 120,
            sleepQualityScore: -10
        )

        XCTAssertEqual(summary.level, 100)
        XCTAssertEqual(summary.stressScore, 0)
        XCTAssertEqual(summary.recoveryScore, 100)
        XCTAssertEqual(summary.drainScore, 100)
        XCTAssertEqual(summary.dailyDrainScore, 0)
        XCTAssertEqual(summary.fatigueLoadScore, 100)
        XCTAssertEqual(summary.sleepQualityScore, 0)
    }

    func testSummaryClampsNonNegativeQuantities() {
        let summary = BodyBatterySummary(
            level: 50,
            stressScore: 10,
            recoveryScore: 10,
            drainScore: 10,
            steps2h: -300,
            activeEnergyKilocalories2h: -10,
            basalEnergyKilocalories2h: -1,
            awakeMinutesToday: -5,
            stepsToday: -1000,
            activeEnergyKilocaloriesToday: -2,
            basalEnergyKilocaloriesToday: -3
        )

        XCTAssertEqual(summary.steps2h, 0)
        XCTAssertEqual(summary.activeEnergyKilocalories2h, 0)
        XCTAssertEqual(summary.basalEnergyKilocalories2h, 0)
        XCTAssertEqual(summary.awakeMinutesToday, 0)
        XCTAssertEqual(summary.stepsToday, 0)
        XCTAssertEqual(summary.activeEnergyKilocaloriesToday, 0)
        XCTAssertEqual(summary.basalEnergyKilocaloriesToday, 0)
    }

    func testFullSummaryHasFullBatteryAndZeroStress() {
        XCTAssertEqual(BodyBatterySummary.full.level, 100)
        XCTAssertEqual(BodyBatterySummary.full.stressScore, 0)
        XCTAssertEqual(BodyBatterySummary.full.recoveryScore, 0)
        XCTAssertEqual(BodyBatterySummary.full.drainScore, 0)
    }

    // MARK: - BodyBatteryBaseline clamp

    func testBaselineClampsFatigueLoadIntoZeroToOneHundred() {
        let tooHigh = BodyBatteryBaseline(fatigueLoadScore: 200)
        let tooLow = BodyBatteryBaseline(fatigueLoadScore: -30)
        let normal = BodyBatteryBaseline(fatigueLoadScore: 55)

        XCTAssertEqual(tooHigh.fatigueLoadScore, 100)
        XCTAssertEqual(tooLow.fatigueLoadScore, 0)
        XCTAssertEqual(normal.fatigueLoadScore, 55)
    }

    // MARK: - BatterySnapshotCodec round-trip

    func testCodecRoundTripsAllFieldsIncludingHRV() {
        let original = BodyBatterySummary(
            level: 73,
            stressScore: 22,
            recoveryScore: 14,
            drainScore: 9,
            dailyDrainScore: 31,
            fatigueLoadScore: 48,
            sleepQualityScore: 67,
            hrvSDNNMilliseconds: 54,
            steps2h: 2_400,
            activeEnergyKilocalories2h: 130,
            basalEnergyKilocalories2h: 78,
            awakeMinutesToday: 410,
            stepsToday: 6_900,
            activeEnergyKilocaloriesToday: 420,
            basalEnergyKilocaloriesToday: 1_050
        )

        let payload = BatterySnapshotCodec.payload(for: original)
        let decoded = BatterySnapshotCodec.summary(from: payload)

        XCTAssertEqual(decoded, original)
    }

    func testCodecRoundTripsWhenHRVIsNil() {
        let original = BodyBatterySummary(
            level: 50,
            stressScore: 10,
            recoveryScore: 8,
            drainScore: 5,
            hrvSDNNMilliseconds: nil
        )

        let decoded = BatterySnapshotCodec.summary(from: BatterySnapshotCodec.payload(for: original))

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.hrvSDNNMilliseconds, nil)
        XCTAssertEqual(decoded?.level, 50)
    }

    func testCodecReturnsNilForEmptyMessage() {
        XCTAssertNil(BatterySnapshotCodec.summary(from: [:]))
    }

    func testCodecReturnsNilForMessageWithoutLevel() {
        // 即使有其它字段，缺 level 也应判定为无效快照。
        let message: [String: Any] = ["stressScore": 10, "recoveryScore": 5]
        XCTAssertNil(BatterySnapshotCodec.summary(from: message))
    }

    func testCodecDecodesLegacyPayloadWithMissingOptionalFields() {
        // 旧版本/部分消息可能只有少数字段，缺失字段应回退为 0，不崩。
        let message: [String: Any] = ["batteryLevel": 42]

        let decoded = BatterySnapshotCodec.summary(from: message)

        XCTAssertEqual(decoded?.level, 42)
        XCTAssertEqual(decoded?.stressScore, 0)
        XCTAssertEqual(decoded?.recoveryScore, 0)
        XCTAssertEqual(decoded?.stepsToday, 0)
        XCTAssertNil(decoded?.hrvSDNNMilliseconds)
    }

    func testCodecUsesStableLevelKey() {
        // WatchConnectivity 历史上用 "batteryLevel" 作为主键，这里锁定它不被误改。
        let payload = BatterySnapshotCodec.payload(for: BodyBatterySummary(level: 88, stressScore: 1, recoveryScore: 1, drainScore: 1))
        XCTAssertEqual(payload["batteryLevel"] as? Int, 88)
    }

    func testRequestPhoneSnapshotKeyIsStable() {
        // 两端必须用同一个键发起/识别快照请求。
        XCTAssertEqual(BatterySnapshotCodec.requestPhoneSnapshotKey, "requestPhoneSnapshot")
    }
}
