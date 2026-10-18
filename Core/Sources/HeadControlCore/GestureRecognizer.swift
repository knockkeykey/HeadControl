import Foundation

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
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func update(_ s: MotionSample, tuning: [String: GestureTuning]) -> Gesture? {
        guard s.finite else { reset(); return nil }
        if let last = lastTime, s.time <= last || s.time - last > 0.4 { reset() }
        lastTime = s.time
        func t(_ g: Gesture) -> GestureTuning { tuning[g.rawValue] ?? .preset(.standard, for: g) }
        let magnitude = max(abs(s.yaw),abs(s.pitch),abs(s.roll))
        let neutral = magnitude <= rearmRange

        if let start = nodSince, s.time - start > t(.nod).completion { nodSince = nil; armed = false }
        if let start = shakeSince, s.time - start > t(.shake).completion { shakeSince = nil; shakeOpposite = false; armed = false }

        if armed {
            if magnitude <= t(.nod).neutral, let start = nodSince, s.time - start >= 0.18, s.time - start <= t(.nod).completion {
                return emit(.nod, time: s.time, tuning: t(.nod))
            }
            if magnitude <= t(.shake).neutral, let start = shakeSince, shakeOpposite, s.time - start >= 0.25, s.time - start <= t(.shake).completion {
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
                if s.time - (candidates[g] ?? s.time) >= t(g).dwell { return emit(g,time:s.time,tuning:t(g)) }
            } else { candidates[g] = nil }
        }
        return nil
    }

    private mutating func emit(_ g: Gesture, time: Double, tuning: GestureTuning) -> Gesture {
        armed = false; nextAllowed = time + tuning.cooldown
        rearmRange = tuning.neutral
        neutralSince = nil; candidates.removeAll(); nodSince = nil; shakeSince = nil; shakeOpposite = false
        return g
    }
}
