import AppKit
import Combine
import CoreMotion

// Compile the real AppController with observable stand-ins; no keys or microphone IO.
@MainActor enum Trace {
    static var events: [String] = []
    static var failKey = false
}
@MainActor final class MotionService: ObservableObject {
    var onSample: ((MotionSample) -> Void)?
    var onInvalidation: ((String) -> Void)?
    var onCalibrationResult: ((String) -> Void)?
    let authorized = true
    @Published var tracking = true
    @Published var calibrated = true
    @Published var walking = false
    @Published var link: HeadphoneLink = .tracking
    @Published var pose = MotionSample(time: 0)
    @Published var sensor = "右耳"
    @Published var calibrating = false
    @Published var calibrationProgress = 0.0
    @Published var calibrationHint = "正对屏幕，保持静止一秒"
    var authorization: CMAuthorizationStatus = .authorized
    func requestPermission() {}
    func reconnect() {}
    func cancelCalibration() { calibrating = false }

    var usage = MotionUsage()
    func setUsage(active: Bool, preview: Bool, pauseWhileWalking: Bool) {
        usage = MotionUsage(active: active, preview: preview, walking: walking && pauseWhileWalking, tracking: tracking)
    }
    func start() {}
    func stop() {}
    func recenter() { onInvalidation?("正在校准"); calibrated = false; calibrating = true }
}
@MainActor final class KeySender {
    var canPost: Bool { true }
    func requestAccess() {}
    func release() {}
    func click(_ shortcut: Shortcut, targetPID: pid_t) async throws {
        Trace.events.append("key")
        if Trace.failKey { throw NSError(domain: "ExpectedTestFailure", code: 1) }
    }
}
@MainActor final class SoundFeedback {
    func prepare(_ names: Set<String>) {}
    func play(_ name: String) throws {
        guard AlertSound.isValid(name) else { throw NSError(domain: "invalid-sound", code: 1) }
        if !name.isEmpty { Trace.events.append("sound:\(name)") }
    }
}
// Also instrument the previous NSSound implementation for the red regression run.
@MainActor final class NSSound {
    let name: String
    init?(named name: String) { self.name = name }
    func stop() {}
    func play() { Trace.events.append("sound:\(name)") }
}

#if !INTERFACE_PROBE
@main struct SoundFeedbackProbe {
    @MainActor static func main() async throws {
        var passed = 0
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("headcontrol-feedback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        for scenario in 0..<9 {
            let store = ConfigurationStore(directory: directory.appendingPathComponent("\(scenario)"))
            store.configuration.sounds[Gesture.tiltLeft.rawValue] = "Submarine"
            if scenario == 2 { store.configuration.bindings[Gesture.tiltLeft.rawValue] = .init(.disabled) }
            if scenario == 4 { store.configuration.bindings[Gesture.tiltLeft.rawValue] = .init(.pause) }
            if scenario == 5 || scenario == 7 { store.configuration.sound = false }
            if scenario == 6 { store.configuration.sounds[Gesture.tiltLeft.rawValue] = "" }
            if scenario == 8 { store.configuration.recognitionEnabled[Gesture.tiltLeft.rawValue] = false }
            let controller = AppController(store: store)
            Trace.events = []; Trace.failKey = scenario == 1
            if scenario == 3 { controller.setTesting(true) } else { controller.setEnabled(true) }
            if scenario == 7 {
                controller.previewSound("Submarine")
            } else {
                for step in 1...50 {
                    controller.motion.onSample?(.init(time: Double(step) * 0.02, roll: step <= 15 ? 0 : -25))
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let expected: [String]
            switch scenario {
            case 0, 1: expected = ["sound:Submarine", "key"]
            case 2, 3, 4, 7: expected = ["sound:Submarine"]
            case 8: expected = []
            default: expected = ["key"]
            }
            guard Trace.events == expected else {
                print("FAIL scenario \(scenario): expected \(expected), got \(Trace.events)")
                exit(1)
            }
            controller.shutdown(); passed += 1
        }
        print("PASS: \(passed) controller feedback cases; sound precedes keys; disabled recognition produces neither sound nor key")

        let store = ConfigurationStore(directory: directory.appendingPathComponent("test-flow"))
        let controller = AppController(store: store)
        controller.startTest(.shake)
        guard controller.testTarget == nil, !controller.testing else { throw failure("disabled gesture started testing") }
        controller.startAllTests()
        guard controller.testTarget == .tiltLeft else { throw failure("wrong first target") }
        var time = 0.0
        func feed(_ seconds: Double, pitch: Double = 0, roll: Double = 0) {
            for _ in 0..<Int(seconds / 0.02) {
                time += 0.02
                controller.motion.onSample?(.init(time: time, pitch: pitch, roll: roll))
            }
        }
        Trace.events = []
        func repeatGesture(_ gesture: Gesture, count: Int = 3) {
            for _ in 0..<count {
                feed(1.1)
                if gesture == .nod { feed(0.24, pitch: -28) }
                else { feed(0.5, roll: gesture == .tiltLeft ? -30 : 30) }
                feed(0.2)
            }
        }
        repeatGesture(.tiltLeft)
        guard controller.testTarget == .tiltRight else { throw failure("wrong second target") }
        repeatGesture(.tiltRight)
        guard controller.testTarget == .nod else { throw failure("wrong third target") }
        repeatGesture(.nod)
        guard controller.testTarget == nil, !controller.testingAll, !controller.testing,
              controller.testPassed == Set([Gesture.tiltLeft, .tiltRight, .nod]),
              !Trace.events.contains("key") else { throw failure("three-attempt test sequence did not finish") }
        guard controller.suggestion(for: .tiltLeft)?.angle == 21,
              controller.practiceCounts[.tiltLeft] == 3 else { throw failure("practice did not use three measurements") }
        store.configuration.sounds[Gesture.nod.rawValue] = "Pop"
        guard controller.testPassed.contains(.nod) else { throw failure("sound-only edit invalidated recognition") }
        store.configuration.tuning[Gesture.nod.rawValue]?.angle += 5
        guard !controller.testPassed.contains(.nod), controller.testPassed.contains(.tiltLeft) else { throw failure("changing recognition parameters kept a stale passed badge or cleared unrelated evidence") }
        controller.startTest(.nod)
        feed(0.3); feed(0.2, pitch: -28)
        store.configuration.recognitionEnabled[Gesture.nod.rawValue] = false
        guard controller.testTarget == nil, !controller.testing else { throw failure("disabled test target stayed active") }
        Trace.events = []; feed(0.1)
        guard Trace.events.isEmpty else { throw failure("disabled partial nod produced feedback") }
        store.configuration.recognitionEnabled = store.configuration.recognitionEnabled.mapValues { _ in false }
        controller.startAllTests()
        guard controller.testTarget == nil, !controller.testing else { throw failure("all-disabled configuration started tests") }
        controller.shutdown()
        print("PASS: three-attempt enabled-only practice, parameter invalidation, sound-only retention, disabled target and all-disabled guards")

        store.configuration = Configuration()
        let joint = AppController(store: store)
        joint.startJointTest(); Trace.events = []
        for step in 1...50 {
            joint.motion.onSample?(.init(time: Double(step) * 0.02, roll: step <= 15 ? 0 : -30))
        }
        guard joint.jointCounts[.tiltLeft] == 1, joint.testPassed.contains(.tiltLeft),
              !Trace.events.contains("key"), !joint.enabled else { throw failure("joint test routed keys or failed to recognize globally") }
        joint.setEverydayObservation(true)
        guard joint.jointCounts.isEmpty, joint.jointLastTrigger == nil else { throw failure("observation phase inherited command counts") }
        for step in 1...50 {
            joint.motion.onSample?(.init(time: 2 + Double(step) * 0.02, roll: step <= 15 ? 0 : 30))
        }
        guard joint.everydayCount == 1, joint.jointCounts[.tiltRight] == 1,
              !joint.testPassed.contains(.tiltRight), !Trace.events.contains("key") else { throw failure("everyday observation marked a command passed or sent a key") }
        store.configuration.tuning[Gesture.tiltLeft.rawValue]?.angle = 40
        guard joint.jointCounts.isEmpty, joint.everydayCount == 0, joint.jointTesting else { throw failure("joint test did not reset evidence after tuning") }
        joint.motion.onInvalidation?("connection changed")
        guard !joint.testing, joint.testPassed.isEmpty, !joint.motion.usage.needsRealtime else { throw failure("invalidation retained test evidence or realtime demand") }
        joint.shutdown()
        print("PASS: joint recognition, daily-action observation, parameter reset and disconnect; no real keys")

        let feedback = AppController(store: store)
        feedback.setEnabled(true)
        guard feedback.motion.usage.needsRealtime else { throw failure("active control lost realtime demand") }
        Trace.failKey = true
        for step in 1...50 {
            feedback.motion.onSample?(.init(time: Double(step) * 0.02, pitch: step <= 15 ? 0 : step <= 27 ? -40 : 0))
        }
        try await Task.sleep(for: .milliseconds(20))
        guard feedback.lastTrigger?.outcome == .skipped, feedback.hudTrigger?.outcome == .skipped,
              feedback.lastTrigger?.message.contains("ExpectedTestFailure") == true else { throw failure("failed key did not publish explicit skipped outcome") }
        feedback.refreshFeedback(now: Date().addingTimeInterval(5))
        guard feedback.hudTrigger == nil, feedback.lastTrigger != nil else { throw failure("transient trigger failed to expire or erased history") }
        feedback.setEnabled(false)
        guard !feedback.motion.usage.needsRealtime else { throw failure("paused controller retained realtime demand") }
        feedback.setPreviewVisible(true, surface: "settings")
        guard feedback.motion.usage.needsPose, !feedback.motion.usage.needsRealtime else { throw failure("paused preview claimed realtime demand") }
        feedback.setPreviewVisible(false, surface: "settings")
        guard !feedback.motion.usage.needsPose else { throw failure("hidden paused controller kept pose demand") }
        feedback.previewSound("Invalid"); feedback.previewSound("Invalid")
        guard feedback.events.first?.count == 2 else { throw failure("repeated event did not preserve count") }
        feedback.shutdown()
        Trace.failKey = false
        print("PASS: skipped-key outcome, transient expiry, preserved history, active/paused/hidden resource demand")

        store.configuration = Configuration()
        let hints = AppController(store: store)
        hints.startJointTest()
        var hintTime = 0.0
        func hintFeed(_ seconds: Double, roll: Double = 0) {
            for _ in 0..<Int(seconds / 0.02) {
                hintTime += 0.02; hints.motion.onSample?(.init(time: hintTime, roll: roll, rate: .init(roll: 5)))
            }
        }
        hintFeed(0.3); hintFeed(0.12, roll: -10); hintFeed(0.1)
        guard hints.blockedHint?.contains("幅度不足") == true else { throw failure("missing insufficient-angle reason") }
        hints.refreshFeedback(now: Date().addingTimeInterval(5))
        guard hints.blockedHint == nil else { throw failure("unfinished-gesture hint did not expire") }
        hintFeed(0.12, roll: -25); hintFeed(0.1)
        guard hints.blockedHint?.contains("保持时间不足") == true else { throw failure("missing insufficient-hold reason") }
        store.configuration.tuning[Gesture.tiltLeft.rawValue]?.speedEnabled = true
        store.configuration.tuning[Gesture.tiltLeft.rawValue]?.speed = 300
        hintFeed(0.3); hintFeed(0.5, roll: -25)
        guard hints.blockedHint?.contains("速度不足") == true else { throw failure("missing slow-gesture reason") }
        hints.refreshFeedback(now: Date().addingTimeInterval(5))
        hintFeed(0.2, roll: -25)
        guard hints.blockedHint == nil else { throw failure("unchanged slow pose renewed an expired hint") }
        hints.shutdown()
        print("PASS: amplitude, dwell and speed failure reasons; expiry without a later successful gesture")

        store.configuration = Configuration()
        store.configuration.tuning[Gesture.tiltLeft.rawValue]?.angle = 40
        let learning = AppController(store: store)
        learning.startTest(.tiltLeft)
        var learningTime = 0.0
        for _ in 0..<3 {
            for step in 1...90 {
                learningTime += 0.02
                learning.motion.onSample?(.init(time: learningTime, roll: step <= 55 || step > 80 ? 0 : -15))
            }
        }
        guard learning.practiceCounts[.tiltLeft] == 3, learning.suggestion(for: .tiltLeft)?.angle == 11,
              !learning.testPassed.contains(.tiltLeft), store.configuration.tuning[Gesture.tiltLeft.rawValue]?.angle == 40 else { throw failure("below-threshold learning failed or silently changed settings") }
        learning.applySuggestion(.tiltLeft)
        guard store.configuration.tuning[Gesture.tiltLeft.rawValue]?.angle == 11,
              store.configuration.tuning[Gesture.tiltLeft.rawValue]?.speedEnabled == false,
              learning.suggestion(for: .tiltLeft) == nil else { throw failure("suggestion did not require manual application or retained stale evidence") }
        learning.shutdown()
        print("PASS: below-threshold practice, manual median suggestion, no false passed badge and no automatic speed switch")

    }
    static func failure(_ message: String) -> NSError { NSError(domain: message, code: 1) }
}
#endif
