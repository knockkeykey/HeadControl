import Foundation

/// A continuous quiet interval, measured relative to its first pose (including yaw wrap).
public struct StablePoseWindow: Sendable {
    public private(set) var progress = 0.0
    private var anchor: MotionSample?
    private var lastTime: Double?
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func update(_ sample: MotionSample) -> Bool {
        guard sample.finite else { reset(); return false }
        let gap = lastTime.map { sample.time <= $0 || sample.time - $0 > 0.4 } ?? false
        lastTime = sample.time
        func distance(_ a: Double, _ b: Double) -> Double {
            abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
        }
        let moving = sample.rate.map { max(abs($0.yaw), abs($0.pitch), abs($0.roll)) > 8 } ?? false
        let displaced = anchor.map { max(distance(sample.yaw, $0.yaw), distance(sample.pitch, $0.pitch), distance(sample.roll, $0.roll)) > 2.5 } ?? true
        if gap || moving || displaced {
            anchor = sample; progress = 0; return false
        }
        progress = min(1, max(0, sample.time - (anchor?.time ?? sample.time)))
        return progress >= 1
    }
}

public struct PracticeAttempt: Equatable, Sendable {
    public var peak: Double
    public var speed: Double?
    public init(peak: Double, speed: Double? = nil) { self.peak = peak; self.speed = speed }
}

/// Measures comfortable excursions independently of the user's existing trigger threshold.
/// An attempt starts near neutral, moves on one dominant axis, and ends after returning.
public struct GesturePractice: Sendable {
    public let gesture: Gesture
    public private(set) var attempts: [PracticeAttempt] = []
    public private(set) var peak = 0.0
    private var lastTime: Double?
    private var ready = false
    private var began: Double?
    private var speed = SpeedPeak()
    private var positive = false
    private var negative = false
    public init(gesture: Gesture) { self.gesture = gesture }
    public var complete: Bool { attempts.count >= 3 }
    public var inProgress: Bool { began != nil }
    public var consistent: Bool {
        guard complete else { return false }
        let peaks = attempts.map(\.peak).sorted()
        return peaks.last! - peaks.first! <= max(8, peaks[peaks.count / 2] * 0.5)
    }
    public mutating func interrupt() {
        ready = false; began = nil; peak = 0; speed = SpeedPeak(); positive = false; negative = false; lastTime = nil
    }
    @discardableResult public mutating func update(_ sample: MotionSample, neutral: Double) -> PracticeAttempt? {
        guard !complete else { return nil }
        guard sample.finite else { interrupt(); return nil }
        if let lastTime, sample.time <= lastTime || sample.time - lastTime > 0.4 { interrupt() }
        lastTime = sample.time
        let other: Double
        let axis: Double
        switch gesture {
        case .tiltLeft, .tiltRight: axis = sample.roll; other = max(abs(sample.yaw), abs(sample.pitch))
        case .turnLeft, .turnRight, .shake: axis = sample.yaw; other = max(abs(sample.roll), abs(sample.pitch))
        case .nod: axis = sample.pitch; other = max(abs(sample.yaw), abs(sample.roll))
        }
        let home = abs(axis) <= min(neutral, 6)
        if began == nil {
            if home { ready = true }
            guard ready, gesture.travel(sample) >= 8, abs(axis) > other * 1.25 else { return nil }
            began = sample.time; peak = 0; speed = SpeedPeak(); positive = false; negative = false
        }
        guard let began else { return nil }
        if sample.time - began > 3 || other > max(12, abs(axis) * 1.25) {
            interrupt(); return nil
        }
        peak = max(peak, gesture.travel(sample))
        if let rate = sample.rate { speed.record(gesture.rate(rate)) }
        if axis >= 8 { positive = true }
        if axis <= -8 { negative = true }
        guard home else { return nil }
        let effective = speed.effective(sequence: gesture.isSequence)
        let attempt = PracticeAttempt(peak: peak, speed: speed.measured && effective > 0 ? effective : nil)
        let valid = sample.time - began >= (gesture == .shake ? 0.25 : 0.18) && peak >= 8 && (gesture != .shake || positive && negative)
        interrupt(); ready = true; lastTime = sample.time
        guard valid else { return nil }
        attempts.append(attempt)
        return attempt
    }
    public var medianPeak: Double? { Self.median(attempts.map(\.peak)) }
    public var medianSpeed: Double? {
        let speeds = attempts.compactMap(\.speed)
        return speeds.count == attempts.count ? Self.median(speeds) : nil
    }
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(); return sorted[sorted.count / 2]
    }
}

/// Resource policy shared with platform code: a hidden, paused app needs neither preview nor real-time priority.
public struct MotionUsage: Equatable, Sendable {
    public var active: Bool
    public var preview: Bool
    public var calibrating: Bool
    public var walking: Bool
    public var tracking: Bool
    public var suspended: Bool
    public init(active: Bool = false, preview: Bool = false, calibrating: Bool = false, walking: Bool = false, tracking: Bool = false, suspended: Bool = false) {
        self.active = active; self.preview = preview; self.calibrating = calibrating
        self.walking = walking; self.tracking = tracking; self.suspended = suspended
    }
    public var needsRealtime: Bool { tracking && !suspended && (calibrating || active && !walking) }
    public var needsPose: Bool { !suspended && (active || preview || calibrating) }
}
