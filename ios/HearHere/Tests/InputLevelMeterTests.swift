import XCTest
@testable import HearHere

final class InputLevelMeterTests: XCTestCase {
    // MARK: - dB Normalization

    func testSilenceNormalizesToZero() {
        let normalized = InputLevelMeter.normalizeDecibels(-160)
        XCTAssertEqual(normalized, 0.0)
    }

    func testFullScaleNormalizesToOne() {
        let normalized = InputLevelMeter.normalizeDecibels(0)
        XCTAssertEqual(normalized, 1.0)
    }

    func testMidRangeNormalizesToHalf() {
        let normalized = InputLevelMeter.normalizeDecibels(-30)
        XCTAssertEqual(normalized, 0.5, accuracy: 0.001)
    }

    func testBelowMinClampsToZero() {
        let normalized = InputLevelMeter.normalizeDecibels(-100)
        XCTAssertEqual(normalized, 0.0)
    }

    func testAboveMaxClampsToOne() {
        let normalized = InputLevelMeter.normalizeDecibels(5)
        XCTAssertEqual(normalized, 1.0)
    }

    // MARK: - Clipping Detection

    func testClippingDetectedAboveThreshold() {
        // -0.5 dB -> normalized = 59.5/60 = ~0.9917, which is >= 0.98
        XCTAssertTrue(InputLevelMeter.isClipping(decibelLevel: -0.5))
    }

    func testNotClippingBelowThreshold() {
        // -1.5 dB -> normalized = 58.5/60 = 0.975, which is < 0.98
        XCTAssertFalse(InputLevelMeter.isClipping(decibelLevel: -1.5))
    }

    func testSilenceIsNotClipping() {
        XCTAssertFalse(InputLevelMeter.isClipping(decibelLevel: -60))
    }

    func testZeroDbIsClipping() {
        XCTAssertTrue(InputLevelMeter.isClipping(decibelLevel: 0))
    }

    // MARK: - Level Clamping

    func testNormalizedLevelIsClampedBetweenZeroAndOne() {
        let low = InputLevelMeter.normalizeDecibels(-200)
        let high = InputLevelMeter.normalizeDecibels(10)
        XCTAssertGreaterThanOrEqual(low, 0.0)
        XCTAssertLessThanOrEqual(low, 1.0)
        XCTAssertGreaterThanOrEqual(high, 0.0)
        XCTAssertLessThanOrEqual(high, 1.0)
    }

    func testMonotonicallyIncreasingNormalizedLevels() {
        let values: [Float] = [-60, -45, -30, -15, 0]
        let normalized = values.map { InputLevelMeter.normalizeDecibels($0) }
        for i in 1..<normalized.count {
            XCTAssertGreaterThan(normalized[i], normalized[i - 1])
        }
    }
}
