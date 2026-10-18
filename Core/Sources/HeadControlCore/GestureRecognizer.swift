import Foundation

/// What the recognizer currently thinks of one gesture, so the UI shows the real decision, not a guess.
public struct GestureStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Just fired (or timed out): ease back a little on this axis before it can fire again.
        case release
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
/// There is no global "return to center" gate: a gesture can start from any pose. A fired (or
/// timed-out) gesture only has to ease back on its own axis before it can fire again.
public struct GestureRecognizer: Sendable {
    private var lastTime: Double?
    private var nextAllowed = -Double.infinity
    /// Gestures that fired or timed out and are waiting for their own axis to ease back.
    private var latched: Set<Gesture> = []
    private var candidates: [Gesture: Double] = [:]
    private var nodSince: Double?
    private var shakeSince: Double?
    private var shakeSign: Double = 0
    private var shakeOpposite = false
    /// Recent angular velocity, long enough to cover the slowest allowed nod or shake.
    private var history: [(time: Double, rate: AxisRates)] = []
    public private(set) var status: [Gesture: GestureStatus] = [:]
    public init() {}
    public mutating func reset() { self = Self() }

    /// Easing back to 70% of the trigger angle re-allows a gesture; nod and shake finish inside neutral anyway.
    static func release(_ t: GestureTuning) -> Double { max(t.neutral, t.angle * 0.7) }
    /// Once a hold has started, natural jitter around the trigger angle should not restart the dwell timer.
    static func hold(_ t: GestureTuning) -> Double { max(release(t), t.angle * 0.8) }

    public mutating func update(_ s: MotionSample, tuning: [String: GestureTuning], enabledGestures: Set<Gesture> = Set(Gesture.allCases)) -> Gesture? {
        let fired = step(s, tuning: tuning, enabledGestures: enabledGestures)
        if s.finite { describe(s, tuning: tuning, enabledGestures: enabledGestures, fired: fired) }
        return fired
    }

    private mutating func step(_ s: MotionSample, tuning: [String: GestureTuning], enabledGestures: Set<Gesture>) -> Gesture? {
        guard s.finite else { reset(); return nil }
        let fresh = lastTime == nil || s.time <= lastTime! || s.time - lastTime! > 0.4
        if fresh { reset() }
        lastTime = s.time
        if let rate = s.rate {
            history.append((s.time, rate))
            if let keep = history.firstIndex(where: { $0.time >= s.time - 2.5 }), keep > 0 { history.removeFirst(keep) }
        }
        func t(_ g: Gesture) -> GestureTuning { tuning[g.rawValue] ?? .defaults(for: g) }
        // A pose already held when tracking (re)starts is not a fresh movement.
        if fresh { latched = Set(enabledGestures.filter { $0.travel(s) > Self.release(t($0)) }) }
        latched = latched.filter { enabledGestures.contains($0) && $0.travel(s) > Self.release(t($0)) }
        candidates = candidates.filter { enabledGestures.contains($0.key) }
        if !enabledGestures.contains(.nod) { nodSince = nil }
        if !enabledGestures.contains(.shake) { shakeSince = nil; shakeOpposite = false }

        if let start = nodSince, s.time - start > t(.nod).completion { nodSince = nil; latched.insert(.nod) }
        if let start = shakeSince, s.time - start > t(.shake).completion { shakeSince = nil; shakeOpposite = false; latched.insert(.shake) }
        guard s.time >= nextAllowed else { candidates.removeAll(); nodSince = nil; shakeSince = nil; shakeOpposite = false; return nil }

        if abs(s.pitch) <= t(.nod).neutral, let start = nodSince, s.time - start >= 0.18, fastEnough(.nod, t(.nod), since: start) {
            return emit(.nod, time: s.time, tuning: t(.nod))
        }
        if abs(s.yaw) <= t(.shake).neutral, let start = shakeSince, shakeOpposite, s.time - start >= 0.25, fastEnough(.shake, t(.shake), since: start) {
            return emit(.shake, time: s.time, tuning: t(.shake))
        }

        // Require the intended axis to dominate; a combined diagonal movement is not two gestures.
        if enabledGestures.contains(.nod), !latched.contains(.nod), -s.pitch >= t(.nod).angle && abs(s.pitch) > max(abs(s.yaw),abs(s.roll)) * 1.25 {
            if nodSince == nil { nodSince = s.time }
        }
        if enabledGestures.contains(.shake), !latched.contains(.shake), abs(s.yaw) >= t(.shake).angle && abs(s.yaw) > max(abs(s.pitch),abs(s.roll)) * 1.25 {
            let sign = s.yaw > 0 ? 1.0 : -1.0
            if shakeSince == nil { shakeSince = s.time; shakeSign = sign; shakeOpposite = false }
            else if sign != shakeSign { shakeOpposite = true }
        }

        let values: [(Gesture, Double, Double)] = [
            (.tiltLeft, -s.roll, max(abs(s.pitch),abs(s.yaw))), (.tiltRight,s.roll,max(abs(s.pitch),abs(s.yaw))),
            (.turnLeft,-s.yaw,max(abs(s.pitch),abs(s.roll))), (.turnRight,s.yaw,max(abs(s.pitch),abs(s.roll)))
        ]
        for (g,value,other) in values where enabledGestures.contains(g) {
            // Crossing the dot needs a clear, dominant tilt; staying in it only needs to remain near it and lead the other axes.
            let holding = candidates[g] != nil
            let inside = holding ? value >= Self.hold(t(g)) && value > other : value >= t(g).angle && value > other * 1.25
            if !latched.contains(g), inside {
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
        guard tuning.speedEnabled, let speed = measuredSpeed(g, since: since) else { return true }
        return speed >= tuning.speed
    }
    private func measuredSpeed(_ g: Gesture, since: Double) -> Double? {
        var peak = SpeedPeak()
        for entry in history where entry.time >= since - 0.4 { peak.record(g.rate(entry.rate)) }
        return peak.measured ? peak.effective(sequence: g.isSequence) : nil
    }

    /// Derived purely from the state `step` left behind, using the same conditions it checks.
    private mutating func describe(_ s: MotionSample, tuning: [String: GestureTuning], enabledGestures: Set<Gesture>, fired: Gesture?) {
        func t(_ g: Gesture) -> GestureTuning { tuning[g.rawValue] ?? .defaults(for: g) }
        var next: [Gesture: GestureStatus] = [:]
        for g in Gesture.allCases where enabledGestures.contains(g) {
            let tg = t(g)
            if g == fired { next[g] = GestureStatus(phase: .fired, progress: 1); continue }
            if fired != nil || s.time < nextAllowed { next[g] = GestureStatus(phase: .cooldown); continue }
            if latched.contains(g) { next[g] = GestureStatus(phase: .release); continue }
            let reached = g.travel(s) >= tg.angle
            switch g {
            case .nod:
                if let start = nodSince {
                    let speed = measuredSpeed(g, since: start)
                    let returned = abs(s.pitch) <= tg.neutral && s.time - start >= 0.18
                    next[g] = GestureStatus(phase: returned ? .tooSlow : .holding, progress: 0.5, speed: speed)
                } else { next[g] = GestureStatus(phase: reached ? .mixed : .below) }
            case .shake:
                if let start = shakeSince {
                    let speed = measuredSpeed(g, since: start)
                    let returned = shakeOpposite && abs(s.yaw) <= tg.neutral && s.time - start >= 0.25
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
        nextAllowed = time + tuning.cooldown; latched.insert(g)
        candidates.removeAll(); nodSince = nil; shakeSince = nil; shakeOpposite = false
        return g
    }
}
