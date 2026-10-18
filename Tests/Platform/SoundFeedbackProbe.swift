import AppKit
import Combine

// Compile the real AppController with observable stand-ins; no keys or microphone IO.
@MainActor enum Trace {
    static var events: [String] = []
    static var failKey = false
}
@MainActor final class MotionService: ObservableObject {
    var onSample: ((MotionSample) -> Void)?
    var onInvalidation: ((String) -> Void)?
    let authorized = true, tracking = true, calibrated = true, walking = false
    func start() {}
    func stop() {}
    func recenter() {}
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
        feed(0.3); feed(0.5, roll: -30)
        guard controller.testTarget == .tiltRight else { throw failure("wrong second target") }
        feed(0.3); feed(0.5, roll: 30)
        guard controller.testTarget == .nod else { throw failure("wrong third target") }
        feed(0.3); feed(0.24, pitch: -28); feed(0.1)
        guard controller.testTarget == nil, !controller.testingAll,
              controller.testPassed == Set([Gesture.tiltLeft, .tiltRight, .nod]),
              !Trace.events.contains("key") else { throw failure("enabled-only test sequence did not finish") }
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
        print("PASS: enabled-only test sequence, disabled single-test guard, cancel disabled target, all-disabled guard")
    }
    static func failure(_ message: String) -> NSError { NSError(domain: message, code: 1) }
}
