import Foundation

/// What the recognizer currently thinks of one gesture, so the UI shows the real decision, not a guess.
public struct GestureStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Not armed: the head has to come back inside the re-arm range first.
        case recenter
        case cooldown
        /// Armed, but the angle is below the trigger point.
        case below
        /// The angle is reached, but another axis is too large for this direction to count.
        case mixed
        /// All gates pass so far: holding (tilt/turn) or waiting for the return stroke (nod/shake).
        case holding
        /// Angle and timing passed, but the movement was slower than the speed gate.
        case tooSlow
        case fired
    }
    public var phase: Phase
    /// Hold progress for tilt/turn, stroke progress for nod/shake, 0...1.
    public var progress: Double
    /// Effective speed (°/s) as measured by the speed gate, when the gate has samples.
    public var speed: Double?
    public init(phase: Phase, progress: Double = 0, speed: Double? = nil) { self.phase = phase; self.progress = progress; self.speed = speed }
}

/// Timestamp-driven recognizer, independent of sensor sample rate and UI refresh.
public struct GestureRecognizer: Sendable {
    private var lastTime: Double?
    private var neutralSince: Double?
    private var armed = false
    private var rearmRange: Double = 7
    private var nextAllowed = -Double.infinity
    private var candidates: [Gesture: Double] = [:]
    private var nodSince: Double?
    private var shakeSince: Double?
    private var shakeSign: Double = 0
    private var shakeOpposite = false
    /// Recent angular velocity, long enough to cover the slowest allowed nod or shake.
    private var history: [(time: Double, rate: AxisRates)] = []
    public private(set) var status: [Gesture: GestureStatus] = [:]
    /// Largest angle on any axis in the last sample; arming needs it within `rearmLimit`.
    public private(set) var offCenter: Double = 0
    public var rearmLimit: Double { rearmRange }
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func update(_ s: MotionSample, tuning: [String: GestureTuning]) -> Gesture? {
        let fired = step(s, tuning: tuning)
        if s.finite { describe(s, tuning: tuning, fired: fired) }
        return fired
    }

    private mutating func step(_ s: MotionSample, tuning: [String: GestureTuning]) -> Gesture? {
        guard s.finite else { reset(); return nil }
        if let last = lastTime, s.time <= last || s.time - last > 0.4 { reset() }
        lastTime = s.time
        if let rate = s.rate {
            history.append((s.time, rate))
            if let keep = history.firstIndex(where: { $0.time >= s.time - 2.5 }), keep > 0 { history.removeFirst(keep) }
        }
        func t(_ g: Gesture) -> GestureTuning { tuning[g.rawValue] ?? .preset(.standard, for: g) }
        let magnitude = max(abs(s.yaw),abs(s.pitch),abs(s.roll))
        let neutral = magnitude <= rearmRange

        if let start = nodSince, s.time - start > t(.nod).completion { nodSince = nil; armed = false }
        if let start = shakeSince, s.time - start > t(.shake).completion { shakeSince = nil; shakeOpposite = false; armed = false }

        if armed {
            if magnitude <= t(.nod).neutral, let start = nodSince, s.time - start >= 0.18, s.time - start <= t(.nod).completion, fastEnough(.nod, t(.nod), since: start) {
                return emit(.nod, time: s.time, tuning: t(.nod))
            }
            if magnitude <= t(.shake).neutral, let start = shakeSince, shakeOpposite, s.time - start >= 0.25, s.time - start <= t(.shake).completion, fastEnough(.shake, t(.shake), since: start) {
                return emit(.shake, time: s.time, tuning: t(.shake))
            }
        }
        if neutral {
            if neutralSince == nil { neutralSince = s.time }
            if s.time - (neutralSince ?? s.time) >= 0.18 && s.time >= nextAllowed { armed = true }
            candidates.removeAll()
            return nil
        }
        neutralSince = nil
        guard armed, s.time >= nextAllowed else { return nil }

        // Require the intended axis to dominate; a combined diagonal movement is not two gestures.
        if -s.pitch >= t(.nod).angle && abs(s.pitch) > max(abs(s.yaw),abs(s.roll)) * 1.25 {
            if nodSince == nil { nodSince = s.time }
        }
        if abs(s.yaw) >= t(.shake).angle && abs(s.yaw) > max(abs(s.pitch),abs(s.roll)) * 1.25 {
            let sign = s.yaw > 0 ? 1.0 : -1.0
            if shakeSince == nil { shakeSince = s.time; shakeSign = sign; shakeOpposite = false }
            else if sign != shakeSign { shakeOpposite = true }
        }

        let values: [(Gesture, Double, Double)] = [
            (.tiltLeft, -s.roll, max(abs(s.pitch),abs(s.yaw))), (.tiltRight,s.roll,max(abs(s.pitch),abs(s.yaw))),
            (.turnLeft,-s.yaw,max(abs(s.pitch),abs(s.roll))), (.turnRight,s.yaw,max(abs(s.pitch),abs(s.roll)))
        ]
        for (g,value,other) in values {
            if value >= t(g).angle && value > other * 1.25 {
                if candidates[g] == nil { candidates[g] = s.time }
                let since = candidates[g] ?? s.time
                if s.time - since >= t(g).dwell, fastEnough(g, t(g), since: since) { return emit(g,time:s.time,tuning:t(g)) }
            } else { candidates[g] = nil }
        }
        return nil
    }

    /// The axis must have moved at least `speed` since just before the angle was crossed.
    /// Nod and shake need that speed both ways, so a quick drop with a slow return does not count.
    private func fastEnough(_ g: Gesture, _ tuning: GestureTuning, since: Double) -> Bool {
        guard let speed = measuredSpeed(g, since: since) else { return true }
        return speed >= tuning.speed
    }
    private func measuredSpeed(_ g: Gesture, since: Double) -> Double? {
        var peak = SpeedPeak()
        for entry in history where entry.time >= since - 0.4 { peak.record(g.rate(entry.rate)) }
        return peak.measured ? peak.effective(sequence: g.isSequence) : nil
    }

    /// Derived purely from the state `step` left behind, using the same conditions it checks.
    private mutating func describe(_ s: MotionSample, tuning: [String: GestureTuning], fired: Gesture?) {
        func t(_ g: Gesture) -> GestureTuning { tuning[g.rawValue] ?? .preset(.standard, for: g) }
        let magnitude = max(abs(s.yaw),abs(s.pitch),abs(s.roll))
        offCenter = magnitude
        var next: [Gesture: GestureStatus] = [:]
        for g in Gesture.allCases {
            let tg = t(g)
            if g == fired { next[g] = GestureStatus(phase: .fired, progress: 1); continue }
            if fired != nil || !armed { next[g] = GestureStatus(phase: s.time < nextAllowed ? .cooldown : .recenter); continue }
            let reached = g.travel(s) >= tg.angle
            switch g {
            case .nod:
                if let start = nodSince {
                    let speed = measuredSpeed(g, since: start)
                    let returned = magnitude <= tg.neutral && s.time - start >= 0.18
                    next[g] = GestureStatus(phase: returned ? .tooSlow : .holding, progress: 0.5, speed: speed)
                } else { next[g] = GestureStatus(phase: reached ? .mixed : .below) }
            case .shake:
                if let start = shakeSince {
                    let speed = measuredSpeed(g, since: start)
                    let returned = shakeOpposite && magnitude <= tg.neutral && s.time - start >= 0.25
                    next[g] = GestureStatus(phase: returned ? .tooSlow : .holding, progress: shakeOpposite ? 0.66 : 0.33, speed: speed)
                } else { next[g] = GestureStatus(phase: reached ? .mixed : .below) }
            default:
                if let since = candidates[g] {
                    let progress = min(1, (s.time - since) / tg.dwell)
                    next[g] = GestureStatus(phase: progress >= 1 ? .tooSlow : .holding, progress: progress, speed: measuredSpeed(g, since: since))
                } else { next[g] = GestureStatus(phase: reached ? .mixed : .below) }
            }
        }
        status = next
    }

    private mutating func emit(_ g: Gesture, time: Double, tuning: GestureTuning) -> Gesture {
        armed = false; nextAllowed = time + tuning.cooldown
        rearmRange = tuning.neutral
        neutralSince = nil; candidates.removeAll(); nodSince = nil; shakeSince = nil; shakeOpposite = false
        return g
    }
}
