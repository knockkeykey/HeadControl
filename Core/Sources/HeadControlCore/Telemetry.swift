import Foundation

public struct SensorVector: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x; self.y = y; self.z = z
    }

    public var magnitude: Double { hypot(hypot(x, y), z) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public func scaled(by factor: Double) -> Self { .init(x: x * factor, y: y * factor, z: z * factor) }
}

/// Estimate the delivered sample rate from sensor timestamps, independently of UI refreshes.
/// A new stream, backwards timestamp, or long gap must not reuse the previous estimate.
public struct MotionCadence: Sendable {
    private var timestamps: [Double] = []
    public private(set) var sampleCount = 0
    public private(set) var frequency: Double?

    public init() {}

    public mutating func record(_ timestamp: Double) {
        guard timestamp.isFinite, timestamp >= 0 else { reset(); return }
        if let previous = timestamps.last, timestamp <= previous || timestamp - previous > 1.5 { reset() }
        timestamps.append(timestamp)
        timestamps.removeAll { $0 < timestamp - 1 }
        sampleCount += 1
        if timestamps.count >= 3, let first = timestamps.first, timestamp > first {
            frequency = Double(timestamps.count - 1) / (timestamp - first)
        } else { frequency = nil }
    }

    public mutating func reset() {
        timestamps.removeAll(keepingCapacity: true)
        sampleCount = 0; frequency = nil
    }
}

/// Digital input levels, not a calibrated acoustic sound-pressure measurement.
public struct AudioSignalLevel: Equatable, Sendable {
    public let rmsDecibels: Double
    public let peakDecibels: Double
    public var meterFraction: Double { min(1, max(0, (rmsDecibels + 60) / 60)) }

    public init?(sumOfSquares: Double, sampleCount: Int, peak: Double) {
        guard sampleCount > 0, sumOfSquares.isFinite, sumOfSquares >= 0, peak.isFinite, peak >= 0 else { return nil }
        rmsDecibels = Self.decibels(sqrt(sumOfSquares / Double(sampleCount)))
        peakDecibels = Self.decibels(peak)
    }

    private static func decibels(_ amplitude: Double) -> Double {
        min(0, max(-100, 20 * log10(max(amplitude, 0.00001))))
    }
}
