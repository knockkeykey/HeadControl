import XCTest
@testable import HeadControlCore

final class TelemetryTests: XCTestCase {
    func testCadenceMeasuresSensorRateRatherThanRefreshRate() {
        var cadence = MotionCadence()
        for index in 0..<80 { cadence.record(100 + Double(index) * 0.02) }
        XCTAssertEqual(cadence.frequency ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(cadence.sampleCount, 80)
    }

    func testCadenceReestimatesAfterDataGapOrTimestampRestart() {
        var cadence = MotionCadence()
        [1.0, 1.02, 1.04].forEach { cadence.record($0) }
        cadence.record(4)
        XCTAssertNil(cadence.frequency)
        XCTAssertEqual(cadence.sampleCount, 1)
        [4.1, 4.2].forEach { cadence.record($0) }
        XCTAssertEqual(cadence.frequency ?? 0, 10, accuracy: 0.001)
        cadence.record(0.5)
        XCTAssertNil(cadence.frequency)
        XCTAssertEqual(cadence.sampleCount, 1)
    }

    func testInvalidAndDuplicateTimestampsCannotProduceAnInfiniteRate() {
        var cadence = MotionCadence()
        [1.0, 1.02, 1.04, 1.04].forEach { cadence.record($0) }
        XCTAssertNil(cadence.frequency)
        cadence.record(.nan)
        XCTAssertNil(cadence.frequency)
        XCTAssertEqual(cadence.sampleCount, 0)
    }

    func testVectorMagnitudeAndAngularUnitConversion() {
        let vector = SensorVector(x: 3, y: 4, z: 0)
        XCTAssertEqual(vector.magnitude, 5)
        XCTAssertEqual(SensorVector(x: .pi, y: 0, z: 0).scaled(by: 180 / .pi).x, 180, accuracy: 0.001)
        XCTAssertFalse(SensorVector(x: .infinity, y: 0, z: 0).isFinite)
    }

    func testMicrophonePowerUsesAmplitudeDecibels() throws {
        let level = try XCTUnwrap(AudioSignalLevel(sumOfSquares: 25, sampleCount: 100, peak: 1))
        XCTAssertEqual(level.rmsDecibels, -6.0206, accuracy: 0.001)
        XCTAssertEqual(level.peakDecibels, 0)
        XCTAssertTrue((0...1).contains(level.meterFraction))
    }

    func testSilenceAndClippingHaveFiniteBoundedLevels() throws {
        let silence = try XCTUnwrap(AudioSignalLevel(sumOfSquares: 0, sampleCount: 100, peak: 0))
        XCTAssertEqual(silence.rmsDecibels, -100)
        XCTAssertEqual(silence.meterFraction, 0)
        let clipped = try XCTUnwrap(AudioSignalLevel(sumOfSquares: 400, sampleCount: 100, peak: 2))
        XCTAssertEqual(clipped.rmsDecibels, 0)
        XCTAssertEqual(clipped.meterFraction, 1)
    }

    func testInvalidAudioBuffersDoNotBecomePlausibleLevels() {
        XCTAssertNil(AudioSignalLevel(sumOfSquares: .nan, sampleCount: 10, peak: 1))
        XCTAssertNil(AudioSignalLevel(sumOfSquares: 1, sampleCount: 0, peak: 1))
        XCTAssertNil(AudioSignalLevel(sumOfSquares: -1, sampleCount: 10, peak: 1))
    }
}
